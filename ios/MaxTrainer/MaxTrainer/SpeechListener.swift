import Foundation
import Speech
import AVFoundation

/// Always-on speech recognition. Delivers one utterance at a time after a short
/// silence, or immediately when `fastPath` recognises a command on the partial text.
/// Pauses itself while Max is talking so the mic does not hear the speaker.
@MainActor
final class SpeechListener: ObservableObject {
    @Published var liveText = ""
    @Published var isListening = false
    @Published var available = true
    @Published var lastError: String?

    /// Called with each complete utterance.
    var onUtterance: ((String) -> Void)?
    /// Called with the partial transcript; return true to consume it right away.
    var fastPath: ((String) -> Bool)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    nonisolated(unsafe) private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var generation = 0
    private var silenceTimer: Timer?
    private var sessionTimer: Timer?
    private var lastText = ""
    private var suppressed = false
    private var running = false
    private var tapInstalled = false

    /// Seconds of no new words before an utterance is considered finished.
    var silenceWindow: TimeInterval = 1.0

    func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard speech == .authorized else { lastError = "Speech recognition not allowed"; return false }
        let mic = await AVAudioApplication.requestRecordPermission()
        if !mic { lastError = "Microphone not allowed" }
        return mic
    }

    func start() {
        guard !running else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                available = false
                lastError = "No microphone input"
                return
            }
            if !tapInstalled {
                input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                    self?.request?.append(buffer)
                }
                tapInstalled = true
            }
            engine.prepare()
            try engine.start()
            running = true
            NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
                guard let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init) else { return }
                Task { @MainActor in
                    if type == .ended { self?.recover() }
                }
            }
            beginRecognition()
        } catch {
            available = false
            lastError = error.localizedDescription
        }
    }

    func stop() {
        running = false
        cancelRecognition()
        if engine.isRunning { engine.stop() }
    }

    /// Pause (true) while Max speaks; resume (false) shortly after he finishes.
    func suppress(_ on: Bool) {
        if on {
            suppressed = true
            cancelRecognition()
        } else {
            suppressed = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                guard let self, !self.suppressed, self.running, self.task == nil else { return }
                self.beginRecognition()
            }
        }
    }

    private func recover() {
        guard running else { return }
        if !engine.isRunning {
            try? AVAudioSession.sharedInstance().setActive(true)
            try? engine.start()
        }
        if !suppressed { restartRecognition() }
    }

    private func beginRecognition() {
        guard running, !suppressed, let recognizer, recognizer.isAvailable else {
            if recognizer?.isAvailable == false { lastError = "Speech recognizer unavailable" }
            return
        }
        cancelRecognition()
        generation += 1
        let gen = generation

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.taskHint = .dictation
        req.addsPunctuation = false
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        request = req
        lastText = ""
        liveText = ""

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            Task { @MainActor in
                guard let self, gen == self.generation else { return }
                self.handle(result: result, error: error)
            }
        }
        isListening = true

        // Recognition sessions are capped at about a minute; roll over before that.
        sessionTimer?.invalidate()
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 50, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, gen == self.generation else { return }
                if self.lastText.isEmpty { self.restartRecognition() } else { self.finalizeUtterance() }
            }
        }
    }

    private func handle(result: SFSpeechRecognitionResult?, error: Error?) {
        if let result {
            let text = result.bestTranscription.formattedString
            if text != lastText {
                lastText = text
                liveText = text
                if fastPath?(text) == true {
                    restartRecognition()
                    return
                }
                silenceTimer?.invalidate()
                silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceWindow, repeats: false) { [weak self] _ in
                    Task { @MainActor in self?.finalizeUtterance() }
                }
            }
            if result.isFinal {
                finalizeUtterance()
                return
            }
        }
        if error != nil {
            // "No speech detected" and friends: just start a fresh session.
            let pending = lastText
            cancelRecognition()
            if !pending.trimmingCharacters(in: .whitespaces).isEmpty { onUtterance?(pending) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, self.running, !self.suppressed, self.task == nil else { return }
                self.beginRecognition()
            }
        }
    }

    private func finalizeUtterance() {
        let text = lastText.trimmingCharacters(in: .whitespacesAndNewlines)
        restartRecognition()
        if !text.isEmpty { onUtterance?(text) }
    }

    private func restartRecognition() {
        cancelRecognition()
        if running && !suppressed { beginRecognition() }
    }

    private func cancelRecognition() {
        silenceTimer?.invalidate()
        sessionTimer?.invalidate()
        generation += 1
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        lastText = ""
        liveText = ""
        isListening = false
    }
}
