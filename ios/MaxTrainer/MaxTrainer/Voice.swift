import Foundation
import AVFoundation

/// Max's voice. `say` returns when the sentence has been spoken.
@MainActor
final class Voice: NSObject, ObservableObject {
    @Published var isSpeaking = false

    var willSpeak: (() -> Void)?
    var didFinish: (() -> Void)?

    private let synth = AVSpeechSynthesizer()
    private var continuations: [AVSpeechUtterance: CheckedContinuation<Void, Never>] = [:]
    private var active = 0
    private lazy var chosenVoice: AVSpeechSynthesisVoice? = Voice.pickVoice()

    override init() {
        super.init()
        synth.delegate = self
        synth.usesApplicationAudioSession = true
    }

    func say(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let u = AVSpeechUtterance(string: trimmed)
            u.voice = chosenVoice
            u.rate = 0.52
            u.pitchMultiplier = 1.0
            u.volume = 1.0
            continuations[u] = cont
            if active == 0 {
                isSpeaking = true
                willSpeak?()
            }
            active += 1
            synth.speak(u)
        }
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
    }

    private func finished(_ u: AVSpeechUtterance) {
        if let c = continuations.removeValue(forKey: u) { c.resume() }
        active = max(0, active - 1)
        if active == 0 {
            isSpeaking = false
            didFinish?()
        }
    }

    static func pickVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "en-US" }
        let ranked = voices.sorted { a, b in
            func score(_ v: AVSpeechSynthesisVoice) -> Int {
                switch v.quality {
                case .premium: return 3
                case .enhanced: return 2
                default: return 1
                }
            }
            return score(a) > score(b)
        }
        return ranked.first ?? AVSpeechSynthesisVoice(language: "en-US")
    }
}

extension Voice: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finished(utterance) }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finished(utterance) }
    }
}
