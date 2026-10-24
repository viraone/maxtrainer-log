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
    private var writer: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var recordingURL: URL?
    private var recordingActive = false

    private let queue = DispatchQueue(label: "com.viraone.maxtrainer.camera")
    private let output = AVCaptureVideoDataOutput()
    private var currentInput: AVCaptureDeviceInput?
    private let lock = NSLock()
    private var latest: CVPixelBuffer?
    private let ciContext = CIContext()

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
        if let conn = output.connection(with: .video) {
            if conn.isVideoRotationAngleSupported(90) { conn.videoRotationAngle = 90 }
            if conn.isVideoMirroringSupported {
                conn.automaticallyAdjustsVideoMirroring = false
                conn.isVideoMirrored = front
            }
        }
        session.commitConfiguration()
    }

    // MARK: - Recording a set

    /// Start writing the live frames to a temporary movie file.
    func startRecording() {
        queue.async { [self] in
            guard !recordingActive else { return }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("set-\(Int(Date().timeIntervalSince1970)).mov")
            try? FileManager.default.removeItem(at: url)
            guard let w = try? AVAssetWriter(outputURL: url, fileType: .mov) else {
                DispatchQueue.main.async { self.recordError = "Could not start recording" }
                return
            }
            writer = w
            writerInput = nil
            adaptor = nil
            recordingURL = url
            recordingActive = true
            DispatchQueue.main.async { self.isRecording = true; self.recordError = nil }
        }
    }

    /// Stop and either save the clip to Photos (named after the exercise) or throw it away.
    func stopRecording(save: Bool, label: String) {
        queue.async { [self] in
            guard recordingActive, let w = writer, let url = recordingURL else { return }
            recordingActive = false
            DispatchQueue.main.async { self.isRecording = false }
            let input = writerInput
            writer = nil; writerInput = nil; adaptor = nil; recordingURL = nil
            guard w.status == .writing, let input else {
                w.cancelWriting()
                try? FileManager.default.removeItem(at: url)
                return
            }
            input.markAsFinished()
            w.finishWriting {
                guard save, w.status == .completed else {
                    try? FileManager.default.removeItem(at: url)
                    return
                }
                self.saveToPhotos(url, label: label)
            }
        }
    }

    private func saveToPhotos(_ url: URL, label: String) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { self.recordError = "Photos access needed to save clips" }
                try? FileManager.default.removeItem(at: url)
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }) { ok, error in
                try? FileManager.default.removeItem(at: url)
                DispatchQueue.main.async {
                    if ok { self.lastClipSaved = Date() } else { self.recordError = error?.localizedDescription ?? "Could not save the clip" }
                }
            }
        }
    }

    /// Called on `queue` for every frame while recording.
    private func record(_ sampleBuffer: CMSampleBuffer, pixelBuffer: CVPixelBuffer) {
        guard recordingActive, let w = writer else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if w.status == .unknown {
            let width = CVPixelBufferGetWidth(pixelBuffer), height = CVPixelBufferGetHeight(pixelBuffer)
            let settings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 6_000_000],
            ]
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.expectsMediaDataInRealTime = true
            guard w.canAdd(input) else { recordingActive = false; return }
            w.add(input)
            adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ])
            writerInput = input
            guard w.startWriting() else { recordingActive = false; return }
            w.startSession(atSourceTime: pts)
        }
        guard w.status == .writing, let input = writerInput, input.isReadyForMoreMediaData else { return }
        adaptor?.append(pixelBuffer, withPresentationTime: pts)
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
        record(sampleBuffer, pixelBuffer: pb)
    }
}
