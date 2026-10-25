import Foundation
import AVFoundation
import UIKit
import CoreImage
import Combine
import Photos

/// Live camera preview plus "grab the latest frame as a JPEG" for form feedback.
final class CameraService: NSObject, ObservableObject {
    let session = AVCaptureSession()
    @Published var isRunning = false
    @Published var unavailable = false
    @Published var isFront = true
    @Published var isRecording = false
    @Published var lastClipSaved: Date?
    @Published var recordError: String?

    // Recording state, touched only on `queue`
    private var clip: ClipWriter?

    private let queue = DispatchQueue(label: "com.viraone.maxtrainer.camera")
    private let output = AVCaptureVideoDataOutput()
    private var currentInput: AVCaptureDeviceInput?
    private let lock = NSLock()
    private var latest: CVPixelBuffer?
    private let ciContext = CIContext()

    // Frame orientation. Touched only on `queue`.
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    private var captureAngle: CGFloat = 90      // degrees clockwise that make frames upright for how the phone stands right now
    private var appliedAngle: CGFloat = 90      // what the frame output is set to; a clip being written keeps its own

    func start(front: Bool) async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        var ok = status == .authorized
        if status == .notDetermined { ok = await AVCaptureDevice.requestAccess(for: .video) }
        guard ok else {
            await MainActor.run { unavailable = true }
            return
        }
        await MainActor.run { isFront = front }
        queue.async { [self] in
            configure(front: front)
            if !session.isRunning { session.startRunning() }
            DispatchQueue.main.async { self.isRunning = self.session.isRunning }
        }
    }

    func flip() {
        let front = !isFront
        isFront = front
        queue.async { [self] in configure(front: front) }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
            DispatchQueue.main.async { self.isRunning = false }
        }
    }

    private func configure(front: Bool) {
        session.beginConfiguration()
        if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
        if let currentInput { session.removeInput(currentInput); self.currentInput = nil }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: front ? .front : .back)
                ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            DispatchQueue.main.async { self.unavailable = true }
            return
        }
        session.addInput(input)
        currentInput = input

        if !session.outputs.contains(output) {
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(output) { session.addOutput(output) }
        }
        // Frames come out upright for the way the phone really stands, so a tripod laid on its side records landscape.
        // The screen stays portrait-locked, so the screen's orientation says nothing about the phone's position.
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        rotationCoordinator = coordinator
        captureAngle = coordinator.videoRotationAngleForHorizonLevelCapture
        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.new]) { [weak self] _, change in
            guard let self, let angle = change.newValue else { return }
            self.queue.async { self.captureAngle = angle; self.applyCaptureAngle() }
        }
        if let conn = output.connection(with: .video), conn.isVideoMirroringSupported {
            conn.automaticallyAdjustsVideoMirroring = false
            conn.isVideoMirrored = front
        }
        applyCaptureAngle()
        session.commitConfiguration()
    }

    /// Turns the frame output to the angle the phone's position calls for. A clip being written keeps the angle it
    /// started with, because its picture size must not change halfway.
    private func applyCaptureAngle() {
        guard let conn = output.connection(with: .video) else { return }
        let angle = clip == nil ? captureAngle : appliedAngle
        if conn.isVideoRotationAngleSupported(angle) {
            if conn.videoRotationAngle != angle { conn.videoRotationAngle = angle }
            appliedAngle = angle
        }
    }

    // MARK: - Recording a set

    /// Starts writing the live frames to a clip file in ClipStorage.
    func startRecording() {
        queue.async { [self] in
            guard clip == nil else { return }
            if let coordinator = rotationCoordinator { captureAngle = coordinator.videoRotationAngleForHorizonLevelCapture }
            applyCaptureAngle()
            guard let c = ClipWriter(url: ClipStorage.newRecordingURL()) else {
                DispatchQueue.main.async { self.recordError = "Could not start recording" }
                return
            }
            clip = c
            DispatchQueue.main.async { self.isRecording = true; self.recordError = nil }
        }
    }

    /// Stops recording. With `keep` the finished clip's URL comes back on the main queue and the caller owns the file.
    /// Without it the recording is thrown away and the URL is nil.
    func stopRecording(keep: Bool, completion: ((URL?) -> Void)? = nil) {
        queue.async { [self] in
            guard let c = clip else {
                DispatchQueue.main.async { completion?(nil) }
                return
            }
            clip = nil
            applyCaptureAngle()                       // catch up with any turn that happened while recording
            DispatchQueue.main.async { self.isRecording = false }
            if !keep {
                c.cancel()
                DispatchQueue.main.async { completion?(nil) }
                return
            }
            c.finish { url in DispatchQueue.main.async { completion?(url) } }
        }
    }

    /// Adds a clip to the Photos library. The file is left in place for the caller to remove.
    func saveToPhotos(_ url: URL, completion: ((Bool) -> Void)? = nil) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { self.recordError = "Photos access needed to save clips"; completion?(false) }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }) { ok, error in
                DispatchQueue.main.async {
                    if ok { self.lastClipSaved = Date() } else { self.recordError = error?.localizedDescription ?? "Could not save the clip" }
                    completion?(ok)
                }
            }
        }
    }

    /// Latest frame, downscaled, as JPEG. Nil when the camera is not running.
    func snapshotJPEG(maxDimension: CGFloat = 768) -> Data? {
        lock.lock()
        let buffer = latest
        lock.unlock()
        guard let buffer else { return nil }
        var image = CIImage(cvPixelBuffer: buffer)
        let longest = max(image.extent.width, image.extent.height)
        if longest > maxDimension {
            let scale = maxDimension / longest
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        guard let cg = ciContext.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cg).jpegData(compressionQuality: 0.7)
    }
}

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lock.lock()
        latest = pb
        lock.unlock()
        clip?.append(pb, at: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    }
}
