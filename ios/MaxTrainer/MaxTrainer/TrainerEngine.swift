import Foundation
import SwiftUI
import Combine
import AudioToolbox

/// The brain: listens, decides, talks, times sets, logs them.
@MainActor
final class TrainerEngine: ObservableObject {
    enum Phase: Equatable {
        case idle        // no exercise chosen
        case ready       // exercise chosen, waiting for "let's go"
        case countdown   // "three, two, one"
        case active      // timer running or reps in progress
        case resting
    }

    @Published var phase: Phase = .idle
    @Published var plan: ExercisePlan?
    @Published var remaining = 0
    @Published var elapsed = 0
    @Published var maxLine = ""
    @Published var heard = ""
    @Published var sessionSets: [WorkoutSet] = []
    @Published var isThinking = false
    @Published var started = false
    @Published var feedbackText: String?
    @Published var lastProblem: String?
    /// Position in the guided ab circuit, nil when not running it.
    @Published var routineIndex: Int?
    /// A guide the view should present ("how do I do this?").
    @Published var showGuide: ExerciseGuide?

    let settings = AppSettings.shared
    let listener = SpeechListener()
    let voice = Voice()
    let camera = CameraService()
    let store = WorkoutLogStore()

    private var timerTask: Task<Void, Never>?
    private var awaitingRepCount = false
    private var midSetFrame: Data?
    private var cancellables = Set<AnyCancellable>()

    /// A line Max has spoken recently, used to reject his own voice coming back through the mic.
    private struct SpokenLine {
        let id: UUID
        let normalized: String
        let words: Set<String>
        let started: Date
        var ended: Date?
    }
    private var spokenLines: [SpokenLine] = []
    /// A phrase heard this soon after Max stops could still be his own words.
    private let echoWindow: TimeInterval = 4.0

    init() {
        // Re-publish child changes so views refresh.
        for child in [listener.objectWillChange.eraseToAnyPublisher(), voice.objectWillChange.eraseToAnyPublisher(),
                      camera.objectWillChange.eraseToAnyPublisher(), store.objectWillChange.eraseToAnyPublisher()] {
            child.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        }
    }

    // MARK: - Lifecycle

    func start() async {
        guard !started else { return }
        started = true
        UIApplication.shared.isIdleTimerDisabled = true

        listener.fastPath = { [weak self] text in self?.consumeFastPath(text) ?? false }
        listener.onUtterance = { [weak self] text in Task { await self?.handle(text, fromMic: true) } }
        voice.willSpeak = { [weak self] in self?.listener.suppress(true) }
        voice.didFinish = { [weak self] in self?.listener.suppress(false) }

        await camera.start(front: settings.useFrontCamera)
        let ok = await listener.requestPermissions()
        if ok {
            // Hold the microphone through the greeting so nothing heard before Max
            // finishes can become a command.
            listener.suppress(true)
            listener.start()
        }
        voice.warmUp()

        await say("Hey, I'm Max. What are we training today? Say it, or tap a move on the screen.")
        if ok { listener.suppress(false) }   // also covers voice being turned off
        Task { await store.sync() }
    }

    var statusText: String {
        if voice.isSpeaking { return "Max is talking" }
        if isThinking { return "Thinking…" }
        switch phase {
        case .active: return plan.map { if case .timed = $0.mode { return "Timer running" } else { return "Say “done” when you finish" } } ?? "Go"
        case .countdown: return "Get ready"
        case .resting: return "Resting"
        case .ready: return listener.isListening ? "Say “let's go baby”" : "Ready"
        case .idle: return listener.isListening ? "Listening" : (listener.available ? "Starting mic…" : "Mic unavailable, type below")
        }
    }

    /// Short description for Claude.
    private var contextDescription: String {
        var lines: [String] = []
        switch phase {
        case .idle: lines.append("Phase: idle, no exercise chosen yet.")
        case .ready: lines.append("Phase: ready, waiting for the user to say go.")
        case .countdown: lines.append("Phase: countdown.")
        case .active: lines.append("Phase: a set is in progress right now.")
        case .resting: lines.append("Phase: rest timer running.")
        }
        if let plan {
            lines.append("Current exercise: \(plan.name), \(plan.shortLabel) per set, \(plan.setsDone) sets done, \(plan.setsRemaining) planned sets remaining.")
        }
        if awaitingRepCount { lines.append("Max just asked how many reps they did; a bare number is that answer.") }
        if !sessionSets.isEmpty {
            lines.append("Logged this session: " + sessionSets.map { "\($0.exercise) \($0.amountLabel)" }.joined(separator: "; "))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Input

    /// Instant commands caught on the partial transcript.
    private func consumeFastPath(_ text: String) -> Bool {
        guard !isEcho(text) else { return false }
        guard let intent = IntentParser.fastPath(text) else { return false }
        switch intent {
        case .go:
            guard phase == .ready || phase == .resting || (phase == .idle && plan != nil) else { return false }
        case .stop:
            guard phase == .active || phase == .countdown || phase == .resting else { return false }
        case .done:
            guard phase == .active else { return false }
        default:
            return false
        }
        heard = text
        Task { await apply(intent, raw: text) }
        return true
    }

    /// A complete utterance (from the mic or typed).
    func handle(_ text: String, fromMic: Bool = false) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if fromMic, isEcho(trimmed) { return }
        heard = trimmed
        var intent = IntentParser.parse(trimmed, strictIdle: fromMic && plan == nil)

        let askClaude: Bool
        switch intent {
        case .plan, .question, .unknown: askClaude = settings.hasClaude
        default: askClaude = false
        }
        if askClaude {
            isThinking = true
            do {
                intent = try await ClaudeService(settings: settings).parseIntent(trimmed, context: contextDescription)
                lastProblem = nil
            } catch {
                lastProblem = error.localizedDescription
            }
            isThinking = false
        }
        await apply(intent, raw: trimmed)
    }

    // MARK: - Decisions

    private func apply(_ intent: Intent, raw: String) async {
        switch intent {
        case .plan(let exercise, let reps, let seconds, let sets):
            guard phase != .active, phase != .countdown else {
                await say("Finish this set first. Tell me if you want to bail.")
                return
            }
            timerTask?.cancel()
            awaitingRepCount = false
            let name = exercise.map(IntentParser.titleCase) ?? plan?.name
            guard let name else {
                await say("Tap a move, or tell me its name and the amount.")
                return
            }
            let sameExercise = plan?.name.lowercased() == name.lowercased()
            if !sameExercise { routineIndex = nil }
            let mode: SetMode
            if let seconds { mode = .timed(seconds: seconds) }
            else if let reps { mode = .reps(target: reps) }
            else if sameExercise, let current = plan?.mode { mode = current }
            else if let guide = ExerciseGuides.find(name) { mode = guide.defaultMode }
            else { mode = .reps(target: nil) }
            let count = sets ?? 1
            plan = ExercisePlan(name: name, mode: mode, setsRemaining: count, setsDone: sameExercise ? (plan?.setsDone ?? 0) : 0)
            phase = .ready
            var line = "Got it. " + (count > 1 ? "\(count) sets of \(plan!.spoken)." : "\(plan!.spoken).")
            if case .reps(nil) = mode { line += " Tell me how many when you're done." }
            line += " Tell me when to start recording you."
            await say(line)

        case .go:
            guard let plan else {
                await say("Tell me the move first. Tap a move, or name it with an amount.")
                return
            }
            guard plan.setsRemaining > 0 else {
                await say("That one's done. Tell me to add sets, or ask for the move after this.")
                return
            }
            guard phase == .ready || phase == .idle || phase == .resting else { return }
            timerTask?.cancel()
            awaitingRepCount = false
            await runSet()

        case .done(let reps):
            if phase == .active, let plan {
                switch plan.mode {
                case .reps(let target): await finishRepSet(reps: reps ?? target)
                case .timed: await finishTimedEarly()
                }
            } else if awaitingRepCount, let reps {
                awaitingRepCount = false
                await logSet(reps: reps, seconds: nil)
            } else if !sessionSets.isEmpty {
                await endSession()
            } else {
                await say("We haven't started yet. What are we doing?")
            }

        case .number(let n):
            if awaitingRepCount {
                awaitingRepCount = false
                await logSet(reps: n, seconds: nil)
            } else if phase == .active, let plan, case .reps = plan.mode {
                await finishRepSet(reps: n)
            } else if phase == .ready, var p = plan {
                switch p.mode {
                case .timed: p.mode = .timed(seconds: n); plan = p; await say("Okay. Tell me when you're set.")
                case .reps: p.mode = .reps(target: n); plan = p; await say("Okay. Tell me when you're set.")
                }
            } else {
                await say("Tell me the move for that number.")
            }

        case .moreSets(let n):
            guard var p = plan else {
                await say("More of what move? Tap it or name it.")
                return
            }
            guard phase != .active, phase != .countdown else { return }
            timerTask?.cancel()
            p.setsRemaining += n
            plan = p
            phase = .ready
            await say("Okay, added to the plan. Tell me when to start recording you.")

        case .stop:
            switch phase {
            case .active, .countdown:
                timerTask?.cancel()
                camera.stopRecording(save: false, label: plan?.name ?? "")
                phase = .ready
                await say("Stopped. Tell me when to start recording you again, or what you want to do.")
            case .resting:
                timerTask?.cancel()
                phase = .ready
                await say("Okay. Tell me when you're set.")
            default:
                break
            }

        case .rest(let seconds):
            guard phase != .active, phase != .countdown else { return }
            await startRest(seconds: seconds ?? 60)

        case .endSession:
            await endSession()

        case .setTime(let s):
            guard var p = plan, phase != .active else { return }
            p.mode = .timed(seconds: s)
            plan = p
            phase = .ready
            await say("\(WorkoutSet.spokenDuration(s)) of \(p.name). Tell me when you're set.")

        case .question:
            await say("I can't answer that without my Claude key. Tell me a move and how long.")

        case .reply(let text):
            await say(text.isEmpty ? "I didn't catch that." : text)

        case .startRoutine:
            guard phase != .active, phase != .countdown else {
                await say("Finish this set first. Tell me if you want to bail.")
                return
            }
            timerTask?.cancel()
            awaitingRepCount = false
            routineIndex = 0
            let first = AbsProgram.steps[0]
            plan = first
            phase = .ready
            await say("Got it. Full circuit, \(AbsProgram.steps.count) moves, three sets each. First up: \(first.spoken). Tell me when to start recording you.")

        case .next:
            guard phase != .active, phase != .countdown else {
                await say("Finish this set first. Tell me if you want to bail.")
                return
            }
            await advanceRoutine(skipped: true)

        case .explain(let name):
            let guide: ExerciseGuide?
            if let name, !name.isEmpty {
                guide = ExerciseGuides.find(name)
            } else if let plan {
                guide = ExerciseGuides.find(plan.name)
            } else {
                guide = nil
            }
            guard let guide else {
                if let name, !name.isEmpty {
                    await say("I don't have a guide for \(name) yet. Pick a move from the list and I'll walk you through it.")
                } else {
                    await say("Pick a move first, then ask me how to do it.")
                }
                return
            }
            showGuide = guide
            await say(guide.spoken)

        case .unknown:
            if raw.split(separator: " ").count >= 3 { await say("I didn't catch that.") }
        }
    }

    // MARK: - Running a set

    private func runSet() async {
        guard let p = plan else { return }
        let setNumber = p.setsDone + 1
        phase = .countdown
        midSetFrame = nil
        elapsed = 0
        if case .timed(let s) = p.mode { remaining = s }
        if settings.recordSets, camera.isRunning, !camera.unavailable { camera.startRecording() }
        AudioServicesPlaySystemSound(1117)   // the "begin recording" tick: instant feedback before Max speaks
        await say("Recording. Set \(setNumber). Three, two, one, go!")
        guard phase == .countdown else { camera.stopRecording(save: false, label: p.name); return }
        phase = .active
        switch p.mode {
        case .timed(let total):
            timerTask = Task { [weak self] in await self?.runTimer(total: total) }
        case .reps:
            timerTask = Task { [weak self] in await self?.runRepClock() }
        }
    }

    private func runTimer(total: Int) async {
        let start = Date()
        var spoken = Set<Int>()
        var halfwaySaid = total < 20
        while !Task.isCancelled {
            let e = Int(Date().timeIntervalSince(start))
            elapsed = e
            remaining = max(0, total - e)
            if e >= total { break }
            if midSetFrame == nil, e >= min(4, max(1, total / 3)) { midSetFrame = camera.snapshotJPEG() }
            if !halfwaySaid, e >= total / 2 {
                halfwaySaid = true
                if midSetFrame == nil { midSetFrame = camera.snapshotJPEG() }
                await say("You're at the halfway point.")
            } else if total > 15, remaining == 10, !spoken.contains(10) {
                spoken.insert(10)
                await say("Ten seconds.")
            } else if remaining <= 5, remaining >= 1, !spoken.contains(remaining) {
                spoken.insert(remaining)
                await say("\(remaining)")
            }
            try? await Task.sleep(for: .milliseconds(150))
        }
        guard !Task.isCancelled else { return }
        remaining = 0
        await finishTimedSet(seconds: total)
    }

    private func runRepClock() async {
        let start = Date()
        var frames = 0
        while !Task.isCancelled {
            elapsed = Int(Date().timeIntervalSince(start))
            if elapsed >= 3, elapsed % 4 == 0, frames < 4 {
                if let f = camera.snapshotJPEG() { midSetFrame = f; frames += 1 }
                try? await Task.sleep(for: .seconds(1))
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    private func finishTimedSet(seconds: Int) async {
        timerTask = nil
        await say("Time!")
        await logSet(reps: nil, seconds: seconds)
    }

    private func finishTimedEarly() async {
        timerTask?.cancel()
        timerTask = nil
        let done = elapsed
        if done >= 3 {
            await say("Okay, stopping at \(done) seconds.")
            await logSet(reps: nil, seconds: done)
        } else {
            camera.stopRecording(save: false, label: plan?.name ?? "")
            phase = .ready
            await say("Cancelled. Tell me when to start recording you.")
        }
    }

    private func finishRepSet(reps: Int?) async {
        timerTask?.cancel()
        timerTask = nil
        if let reps {
            await logSet(reps: reps, seconds: nil)
        } else {
            phase = .ready
            awaitingRepCount = true
            await say("Nice. How many reps?")
        }
    }

    private func logSet(reps: Int?, seconds: Int?) async {
        guard var p = plan else { return }
        camera.stopRecording(save: true, label: p.name)
        p.setsDone += 1
        p.setsRemaining = max(0, p.setsRemaining - 1)
        plan = p
        var set = WorkoutSet(exercise: p.name, reps: reps, durationSeconds: seconds, setNumber: p.setsDone, timestamp: WorkoutSet.isoNow())
        set.summary = "\(p.name): \(set.amountLabel)."
        store.append(set)
        sessionSets.append(set)
        phase = .ready
        if p.setsRemaining > 0 {
            await say("Logged. Tell me when to start recording you.")
        } else if routineIndex != nil {
            await say("Okay, that's logged and saved.")
            await advanceRoutine(skipped: false)
        } else {
            await say("Logged. Nice work on \(p.name). Tell me to add sets, or ask for the move after this.")
        }
        let frame = midSetFrame
        midSetFrame = nil
        Task { await feedbackAndSync(set: set, frame: frame) }
    }

    private func feedbackAndSync(set: WorkoutSet, frame: Data?) async {
        if settings.hasClaude, settings.formFeedback, let frame {
            isThinking = true
            do {
                let fb = try await ClaudeService(settings: settings).formFeedback(frame: frame, set: set)
                var updated = set
                updated.summary = fb.summary
                updated.cues = fb.cues
                updated.improvements = fb.improvements
                store.update(updated)
                if let i = sessionSets.firstIndex(where: { $0.id == set.id }) { sessionSets[i] = updated }
                let spoken = [fb.summary, fb.improvements.first].compactMap { $0 }.joined(separator: " ")
                feedbackText = spoken
                lastProblem = nil
                if phase == .ready || phase == .idle { await say(spoken) }
            } catch {
                lastProblem = error.localizedDescription
            }
            isThinking = false
        }
        if await store.sync() == false, settings.hasGitHub {
            try? await Task.sleep(for: .seconds(15))
            await store.sync()
        }
    }

    private func startRest(seconds: Int) async {
        timerTask?.cancel()
        phase = .resting
        remaining = seconds
        await say("Recovery time. Just breathe.")
        timerTask = Task { [weak self] in
            let start = Date()
            while !Task.isCancelled {
                let e = Int(Date().timeIntervalSince(start))
                await MainActor.run { self?.remaining = max(0, seconds - e) }
                if e >= seconds { break }
                try? await Task.sleep(for: .milliseconds(200))
            }
            guard !Task.isCancelled, let self else { return }
            self.phase = .ready
            await self.say("Break's over. Tell me when you're set.")
        }
    }

    private func endSession() async {
        timerTask?.cancel()
        timerTask = nil
        routineIndex = nil
        phase = .idle
        awaitingRepCount = false
        let sets = sessionSets
        guard !sets.isEmpty else {
            await say("Nothing logged yet. Tell me the move whenever you want.")
            plan = nil
            return
        }
        var summary = templateSummary(sets)
        if settings.hasClaude {
            isThinking = true
            if let s = try? await ClaudeService(settings: settings).sessionSummary(sets) { summary = s }
            isThinking = false
        }
        await say(summary)
        sessionSets = []
        plan = nil
        let synced = await store.sync()
        if settings.hasGitHub {
            await say(synced ? "It's all on your dashboard. Tell me when you want to train again." : "Saved on the phone. I'll push it to the dashboard when I can.")
        } else {
            await say("Saved on the phone. Add a GitHub token in settings and I'll push it to your dashboard.")
        }
    }

    private func templateSummary(_ sets: [WorkoutSet]) -> String {
        var order: [String] = []
        var byName: [String: [WorkoutSet]] = [:]
        for s in sets {
            if byName[s.exercise] == nil { order.append(s.exercise) }
            byName[s.exercise, default: []].append(s)
        }
        let parts = order.map { name -> String in
            let group = byName[name]!
            let reps = group.compactMap(\.reps).reduce(0, +)
            let secs = group.compactMap(\.durationSeconds).reduce(0, +)
            var amount = ""
            if reps > 0 { amount = "\(reps) reps" }
            if secs > 0 { amount += (amount.isEmpty ? "" : " and ") + WorkoutSet.spokenDuration(secs) }
            return "\(group.count) \(group.count == 1 ? "set" : "sets") of \(name)" + (amount.isEmpty ? "" : ", \(amount)")
        }
        return "Nice work. \(sets.count) \(sets.count == 1 ? "set" : "sets") total: " + parts.joined(separator: "; ") + "."
    }

    // MARK: - Six-pack circuit

    /// Move on to the next exercise of the guided circuit (after finishing one, or when the user skips).
    private func advanceRoutine(skipped: Bool) async {
        guard let i = routineIndex else {
            await say("Ask me for the guided workout and I'll run it.")
            return
        }
        let finished = plan?.name ?? "that one"
        let next = i + 1
        if next < AbsProgram.steps.count {
            routineIndex = next
            let step = AbsProgram.steps[next]
            plan = step
            phase = .ready
            let lead = skipped ? "Skipping \(finished)." : "\(finished) done."
            await say("\(lead) \(step.name) is coming up. Tell me when to start recording you.")
        } else {
            routineIndex = nil
            phase = .ready
            await say(skipped ? "That was the last move." : "That's the whole workout. Nice work.")
            await say("Tell me when you're done training, or ask for extra sets.")
        }
    }

    /// One-tap pick from the home screen.
    func choose(_ name: String, mode: SetMode, sets: Int = 3) async {
        switch mode {
        case .timed(let s): await apply(.plan(exercise: name, reps: nil, seconds: s, sets: sets), raw: name)
        case .reps(let r): await apply(.plan(exercise: name, reps: r, seconds: nil, sets: sets), raw: name)
        }
    }

    // MARK: - Speaking

    func say(_ text: String) async {
        maxLine = text
        guard settings.voiceEnabled else { return }
        let spokenID = noteSpoken(text)
        await voice.say(text)
        if let spokenID { finishSpoken(spokenID) }
    }

    func stopTalking() { voice.stop() }

    /// Remember a line as Max starts speaking it.
    private func noteSpoken(_ text: String) -> UUID? {
        let normalized = IntentParser.normalize(text)
        guard !normalized.isEmpty else { return nil }
        let line = SpokenLine(id: UUID(), normalized: normalized,
                              words: Set(normalized.split(separator: " ").map(String.init)),
                              started: Date())
        spokenLines.append(line)
        spokenLines.removeAll { ($0.ended ?? $0.started) < Date().addingTimeInterval(-10) }
        return line.id
    }

    private func finishSpoken(_ id: UUID) {
        guard let i = spokenLines.firstIndex(where: { $0.id == id }) else { return }
        spokenLines[i].ended = Date()
    }

    /// True when `text` is probably Max's own voice coming back through the mic: he is
    /// talking right now, or every word of it is in something he said in the last few seconds.
    private func isEcho(_ text: String) -> Bool {
        if voice.isSpeaking { return true }
        let normalized = IntentParser.normalize(text)
        guard !normalized.isEmpty else { return true }
        let words = Set(normalized.split(separator: " ").map(String.init))
        let now = Date()
        for line in spokenLines.reversed() {
            // Lines still playing are covered by isSpeaking above.
            guard let ended = line.ended, now.timeIntervalSince(ended) <= echoWindow else { continue }
            if line.normalized.contains(normalized) { return true }
            if !words.isEmpty, words.isSubset(of: line.words) { return true }
        }
        return false
    }
}
