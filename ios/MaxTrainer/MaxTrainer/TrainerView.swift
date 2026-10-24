import SwiftUI
import AVFoundation

struct TrainerView: View {
    @EnvironmentObject var engine: TrainerEngine
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var showLog = false
    @State private var showTyping = false
    @State private var typed = ""
    @FocusState private var typingFocused: Bool
    @State private var guide: ExerciseGuide?

    var body: some View {
        ZStack {
            CameraPreview(camera: engine.camera)
                .ignoresSafeArea()
            if engine.camera.unavailable || !engine.camera.isRunning {
                LinearGradient(colors: [Color(red: 0.05, green: 0.06, blue: 0.08), Color(red: 0.11, green: 0.12, blue: 0.16)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                VStack(spacing: 8) {
                    Image(systemName: "camera.fill").font(.system(size: 40)).foregroundStyle(.secondary)
                    Text(engine.camera.unavailable ? "Camera unavailable" : "Starting camera…").foregroundStyle(.secondary)
                }
            }
            LinearGradient(colors: [.black.opacity(0.55), .clear, .clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                topBar
                Spacer()
                centerPiece
                Spacer()
                bottomCard
            }
        }
        .task { await engine.start() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showLog) { LogView().environmentObject(engine) }
        .sheet(item: $guide) { g in ExerciseGuideView(guide: g).environmentObject(engine) }
        .onChange(of: engine.showGuide) { _, g in
            if let g { guide = g; engine.showGuide = nil }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await engine.store.sync() } }
        }
    }

    // MARK: - Top

    private var topBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Text("MAX").font(.system(size: 20, weight: .black, design: .rounded)).foregroundStyle(Color.accent)
                Text("TRAINER").font(.system(size: 20, weight: .black, design: .rounded)).foregroundStyle(.white)
            }
            .fixedSize()
            .layoutPriority(2)
            Spacer(minLength: 6)
            if engine.camera.isRecording {
                HStack(spacing: 5) {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Text("REC").font(.caption.weight(.black))
                }
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(.red.opacity(0.22), in: Capsule())
            }
            statusPill
            Button { showLog = true } label: { Image(systemName: "list.bullet.rectangle").font(.title3) }
            Button { showSettings = true } label: { Image(systemName: "gearshape.fill").font(.title3) }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle().fill(statusColor).frame(width: 8, height: 8)
            Text(engine.statusText).font(.caption.weight(.semibold)).lineLimit(1)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .layoutPriority(0)
    }

    private var statusColor: Color {
        if engine.voice.isSpeaking { return Color.accent }
        if engine.isThinking { return .blue }
        switch engine.phase {
        case .active: return .green
        case .resting: return .blue
        default: return engine.listener.isListening ? .green : .gray
        }
    }

    // MARK: - Center

    @ViewBuilder
    private var centerPiece: some View {
        switch engine.phase {
        case .active:
            if let plan = engine.plan, case .timed = plan.mode {
                bigClock(engine.remaining, label: plan.name.uppercased())
            } else {
                VStack(spacing: 6) {
                    Text(clock(engine.elapsed)).font(.system(size: 64, weight: .bold, design: .rounded)).monospacedDigit()
                    Text("Say “done” or “I did 12”").font(.headline).foregroundStyle(.white.opacity(0.85))
                }
                .foregroundStyle(.white)
                .shadow(radius: 8)
            }
        case .resting:
            bigClock(engine.remaining, label: "REST")
        case .countdown:
            Text("GET READY").font(.system(size: 44, weight: .black, design: .rounded)).foregroundStyle(Color.accent).shadow(radius: 8)
        default:
            EmptyView()
        }
    }

    private func bigClock(_ seconds: Int, label: String) -> some View {
        VStack(spacing: 4) {
            Text(label).font(.headline.weight(.bold)).foregroundStyle(.white.opacity(0.85)).tracking(2)
            Text(clock(seconds))
                .font(.system(size: 120, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(seconds <= 5 && seconds > 0 ? Color.accent : .white)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.15), value: seconds)
        }
        .shadow(color: .black.opacity(0.6), radius: 14)
    }

    private func clock(_ s: Int) -> String {
        s >= 60 ? String(format: "%d:%02d", s / 60, s % 60) : "\(s)"
    }

    // MARK: - Bottom

    private var bottomCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let plan = engine.plan {
                HStack {
                    Text(plan.name).font(.title3.weight(.bold))
                    if let g = ExerciseGuides.find(plan.name) {
                        Button { guide = g } label: {
                            Image(systemName: "questionmark.circle.fill").font(.body).foregroundStyle(Color.accent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("How to do \(plan.name)")
                    }
                    Text("·").foregroundStyle(.secondary)
                    Text(plan.shortLabel).font(.title3.weight(.semibold)).foregroundStyle(Color.accent)
                    Spacer()
                    Text(setsLabel(plan)).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                }
            } else {
                Text("SIX-PACK FOCUS").font(.caption.weight(.black)).tracking(1.6).foregroundStyle(Color.accent)
                Text("Build your abs").font(.title2.weight(.heavy))
                Text("Say “let's do planks”, then “let's go baby” when you're in position. Or say “start the ab workout” for the full circuit. Tap a move to see how it's done.")
                    .font(.footnote).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(AbsProgram.quickPicks, id: \.name) { pick in
                            Button {
                                if let g = ExerciseGuides.find(pick.name) { guide = g }
                                else { Task { await engine.choose(pick.name, mode: pick.mode) } }
                            } label: {
                                HStack(spacing: 5) {
                                    Text(pick.label).font(.footnote.weight(.semibold))
                                    Image(systemName: "questionmark.circle").font(.caption2).foregroundStyle(Color.accent)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(Capsule().fill(Color.white.opacity(0.12)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if !engine.maxLine.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Text("MAX").font(.caption.weight(.black)).foregroundStyle(Color.accent).padding(.top, 2)
                    Text(engine.maxLine).font(.body)
                }
            }
            let live = engine.listener.liveText
            if !live.isEmpty || !engine.heard.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Text("YOU").font(.caption.weight(.black)).foregroundStyle(.secondary).padding(.top, 2)
                    Text(live.isEmpty ? engine.heard : live).font(.body).foregroundStyle(live.isEmpty ? .secondary : .primary).lineLimit(2)
                }
            }

            if showTyping {
                HStack {
                    TextField("Type a command…", text: $typed)
                        .textFieldStyle(.roundedBorder)
                        .focused($typingFocused)
                        .submitLabel(.send)
                        .onSubmit(sendTyped)
                    Button(action: sendTyped) { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                        .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            if !settings.hasGitHub {
                Button { showSettings = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "icloud.slash").font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sets stay on this phone").font(.subheadline.weight(.bold))
                            Text("Add your GitHub token and every set lands on your dashboard the moment it ends.").font(.caption)
                        }
                        Spacer()
                        Text("Add").font(.subheadline.weight(.bold))
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.accent.opacity(0.18)))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.accent.opacity(0.5)))
                }
                .buttonStyle(.plain)
            } else {
                syncStatus
            }

            HStack(spacing: 10) {
                primaryButton
                Button { engine.camera.flip() } label: { Image(systemName: "arrow.triangle.2.circlepath.camera") }
                    .buttonStyle(.bordered)
                Button {
                    showTyping.toggle()
                    typingFocused = showTyping
                } label: { Image(systemName: "keyboard") }
                    .buttonStyle(.bordered)
            }
            if let problem = engine.lastProblem ?? engine.store.lastSyncError ?? engine.listener.lastError {
                Text(problem).font(.caption2).foregroundStyle(.red).lineLimit(2)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    /// One line under the card: where your sets are right now.
    @ViewBuilder
    private var syncStatus: some View {
        let store = engine.store
        let pending = store.pending.count
        if store.isSyncing {
            Label("Logging to your dashboard…", systemImage: "arrow.triangle.2.circlepath").font(.caption).foregroundStyle(.secondary)
        } else if pending > 0 {
            Button { Task { await store.sync() } } label: {
                Label("\(pending) \(pending == 1 ? "set" : "sets") waiting to sync · tap to retry", systemImage: "icloud.slash")
                    .font(.caption).foregroundStyle(Color.accent)
            }
            .buttonStyle(.plain)
        } else if let d = store.lastSyncDate {
            Label("On your dashboard · \(d.formatted(date: .omitted, time: .shortened))", systemImage: "checkmark.icloud.fill")
                .font(.caption).foregroundStyle(.green)
        } else if !engine.sessionSets.isEmpty {
            Label("On your dashboard", systemImage: "checkmark.icloud.fill").font(.caption).foregroundStyle(.green)
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch engine.phase {
        case .ready, .resting:
            bigButton("LET'S GO BABY", color: Color.accent) { Task { await engine.handle("let's go") } }
        case .active:
            if let plan = engine.plan, case .timed = plan.mode {
                bigButton("STOP", color: .red) { Task { await engine.handle("stop") } }
            } else {
                bigButton("DONE", color: .green) { Task { await engine.handle("done") } }
            }
        case .countdown:
            bigButton("STOP", color: .red) { Task { await engine.handle("stop") } }
        case .idle:
            if engine.plan != nil {
                bigButton("LET'S GO BABY", color: Color.accent) { Task { await engine.handle("let's go") } }
            } else {
                bigButton("START AB WORKOUT", color: Color.accent) { Task { await engine.handle("start the ab workout") } }
            }
        }
    }

    private func bigButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.headline.weight(.black)).frame(maxWidth: .infinity).padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(color)
    }

    private func setsLabel(_ plan: ExercisePlan) -> String {
        let total = plan.setsDone + plan.setsRemaining
        let base = (total <= 1 && plan.setsDone == 0) ? "Set 1" : "Set \(min(plan.setsDone + 1, max(total, 1))) of \(max(total, 1))"
        if let i = engine.routineIndex { return "Move \(i + 1)/\(AbsProgram.steps.count) · " + base }
        return base
    }

    private func sendTyped() {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        typed = ""
        Task { await engine.handle(text) }
    }
}

extension Color {
    static let accent = Color(red: 0.96, green: 0.65, blue: 0.14)
}

/// AVCaptureVideoPreviewLayer wrapped for SwiftUI.
struct CameraPreview: UIViewRepresentable {
    let camera: CameraService

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.previewLayer.session = camera.session
        v.previewLayer.videoGravity = .resizeAspectFill
        v.backgroundColor = .black
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
