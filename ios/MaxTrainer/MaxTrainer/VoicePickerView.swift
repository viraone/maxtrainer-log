import SwiftUI
import AVFoundation

/// Pick the voice Max speaks with, with a preview of each installed voice.
struct VoicePickerView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var voices = Voice.installedVoices()
    @State private var previewing: String?
    private let synth = AVSpeechSynthesizer()

    private var natural: [AVSpeechSynthesisVoice] { voices.filter { $0.quality != .default } }
    private var basic: [AVSpeechSynthesisVoice] { voices.filter { $0.quality == .default } }

    var body: some View {
        List {
            if natural.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Only basic voices are installed", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.bold)).foregroundStyle(Color.accent)
                        Text("These are the robotic ones. Apple's natural voices are a free download, about 100 MB each:")
                            .font(.footnote)
                        VStack(alignment: .leading, spacing: 4) {
                            step(1, "Open the iPhone **Settings** app")
                            step(2, "**Accessibility** → **Read & Speak** (called **Spoken Content** on older iOS) → **Voices**")
                            step(3, "**English** → pick a voice → tap the download icon")
                            step(4, "Good picks: **Evan**, **Nathan**, **Tom** (Enhanced) or **Ava**, **Zoe** (Premium)")
                            step(5, "Come back here and choose it")
                        }
                        .font(.footnote)
                        Text("Voices marked Premium sound the most human.").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                row(name: "Automatic", detail: "Best installed voice", id: "", quality: nil)
            } footer: {
                Text("Automatic picks the highest-quality English voice on this phone.")
            }

            if !natural.isEmpty {
                Section("Natural voices") {
                    ForEach(natural, id: \.identifier) { v in
                        row(name: v.name, detail: region(v), id: v.identifier, quality: v.quality)
                    }
                }
            }
            Section("Basic voices") {
                ForEach(basic, id: \.identifier) { v in
                    row(name: v.name, detail: region(v), id: v.identifier, quality: v.quality)
                }
            }
        }
        .navigationTitle("Max's voice")
        .onAppear { voices = Voice.installedVoices() }
        .onDisappear { synth.stopSpeaking(at: .immediate) }
    }

    private func row(name: String, detail: String, id: String, quality: AVSpeechSynthesisVoiceQuality?) -> some View {
        HStack(spacing: 12) {
            Button {
                preview(id)
            } label: {
                Image(systemName: previewing == id ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title2).foregroundStyle(Color.accent)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name).font(.body.weight(.semibold))
                    if let quality {
                        Text(quality == .premium ? "PREMIUM" : quality == .enhanced ? "ENHANCED" : "BASIC")
                            .font(.caption2.weight(.black)).tracking(0.8)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(quality == .default ? Color.gray.opacity(0.3) : Color.accent.opacity(0.25)))
                            .foregroundStyle(quality == .default ? .secondary : Color.accent)
                    }
                }
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if settings.voiceIdentifier == id {
                Image(systemName: "checkmark").font(.body.weight(.bold)).foregroundStyle(Color.accent)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { settings.voiceIdentifier = id; preview(id) }
    }

    private func preview(_ id: String) {
        if previewing == id {
            synth.stopSpeaking(at: .immediate); previewing = nil; return
        }
        synth.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: "Hey, I'm Max. Let's do planks, thirty seconds. Tell me when to start recording you.")
        u.voice = id.isEmpty ? Voice.pickVoice() : AVSpeechSynthesisVoice(identifier: id)
        u.rate = 0.5
        previewing = id
        synth.speak(u)
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { if previewing == id { previewing = nil } }
    }

    private func region(_ v: AVSpeechSynthesisVoice) -> String {
        let locale = Locale(identifier: v.language)
        let country = locale.region.flatMap { Locale.current.localizedString(forRegionCode: $0.identifier) } ?? v.language
        let gender = v.gender == .male ? "Male" : v.gender == .female ? "Female" : ""
        return [country, gender].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(n).").foregroundStyle(.secondary).frame(width: 18, alignment: .trailing)
            Text(.init(text))
        }
    }
}
