import AVFoundation
import CoreVideo
import Foundation

/// Turns camera frames into a small H.264 .mp4 that is cheap to upload and still good enough to review form.
/// Phone frames come in at 720x1280; the clip is scaled to 540x960 (or 960x540 when landscape) at about 1 Mbps
/// and 20 frames per second, which is roughly 3.5 MB for 30 seconds.
/// Not thread-safe: call every method from the same serial queue.
final class ClipWriter {
    static let longSide = 960
    static let shortSide = 540
    static let bitrate = 1_000_000
    static let frameInterval = CMTime(value: 1, timescale: 20)

    let url: URL
    private let writer: AVAssetWriter
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var nextDue = CMTime.invalid
    private var sourceSize: (w: Int, h: Int)?
    private var failed = false
    private(set) var framesWritten = 0

    init?(url: URL) {
        self.url = url
        try? FileManager.default.removeItem(at: url)
        guard let w = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return nil }
        writer = w
    }

    func append(_ pixelBuffer: CVPixelBuffer, at pts: CMTime) {
        guard !failed else { return }
        if writer.status == .unknown {
            let w = CVPixelBufferGetWidth(pixelBuffer), h = CVPixelBufferGetHeight(pixelBuffer)
            let portrait = h >= w
            let settings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: portrait ? Self.shortSide : Self.longSide,
                AVVideoHeightKey: portrait ? Self.longSide : Self.shortSide,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: Self.bitrate,
                    AVVideoMaxKeyFrameIntervalKey: 40,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264MainAutoLevel,
                    AVVideoExpectedSourceFrameRateKey: 20,
                ],
            ]
            let inp = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            inp.expectsMediaDataInRealTime = true
            let ad = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: inp, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: w,
                kCVPixelBufferHeightKey as String: h,
            ])
            guard writer.canAdd(inp) else { failed = true; return }
            writer.add(inp)
            guard writer.startWriting() else { failed = true; return }
            writer.startSession(atSourceTime: pts)
            input = inp
            adaptor = ad
            sourceSize = (w, h)
        }
        // The phone can be turned between frames. A frame of another size would break the clip, so it is skipped.
        guard let src = sourceSize, CVPixelBufferGetWidth(pixelBuffer) == src.w, CVPixelBufferGetHeight(pixelBuffer) == src.h else { return }
        guard writer.status == .writing, let input, let adaptor, input.isReadyForMoreMediaData else { return }
        // Keep frames on a 20 fps schedule: a 30 fps camera loses every third frame.
        if nextDue.isValid, CMTimeCompare(pts, CMTimeSubtract(nextDue, CMTime(value: 4, timescale: 1000))) < 0 { return }
        if adaptor.append(pixelBuffer, withPresentationTime: pts) {
            var due = nextDue.isValid ? CMTimeAdd(nextDue, Self.frameInterval) : CMTimeAdd(pts, Self.frameInterval)
            if CMTimeCompare(due, pts) <= 0 { due = CMTimeAdd(pts, Self.frameInterval) }   // fell behind: resync
            nextDue = due
            framesWritten += 1
        } else {
            failed = true
        }
    }

    /// Finishes the file. The completion gets the URL if a usable clip was written, otherwise nil and the file is gone.
    func finish(completion: @escaping (URL?) -> Void) {
        guard writer.status == .writing, let input, framesWritten > 0, !failed else {
            cancel()
            completion(nil)
            return
        }
        input.markAsFinished()
        let url = self.url, writer = self.writer
        writer.finishWriting {
            if writer.status == .completed {
                completion(url)
            } else {
                try? FileManager.default.removeItem(at: url)
                completion(nil)
            }
        }
    }

    /// Throws the recording away.
    func cancel() {
        if writer.status == .writing || writer.status == .unknown { writer.cancelWriting() }
        try? FileManager.default.removeItem(at: url)
    }
}
