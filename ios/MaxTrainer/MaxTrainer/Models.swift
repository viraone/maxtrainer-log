import Foundation

/// One logged set. Mirrors an entry in data/workouts.json (the dashboard's file),
/// plus local-only bookkeeping (`id`, `synced`).
struct WorkoutSet: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var exercise: String
    var reps: Int?
    var durationSeconds: Int?
    var setNumber: Int?
    var timestamp: String
    var summary: String?
    var cues: [String] = []
    var improvements: [String] = []
    var synced: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, exercise, reps, timestamp, summary, cues, improvements, synced
        case durationSeconds = "duration_seconds"
        case setNumber = "set_number"
    }

    /// The shape written to data/workouts.json, which the dashboard reads.
    var remoteJSON: [String: Any] {
        var d: [String: Any] = [
            "exercise": exercise,
            "timestamp": timestamp,
            "cues": cues,
            "improvements": improvements,
            "summary": summary ?? "",
        ]
        if let reps { d["reps"] = reps }
        if let durationSeconds { d["duration_seconds"] = durationSeconds }
        if let setNumber { d["set_number"] = setNumber }
        return d
    }

    /// "30 seconds" / "12 reps", for speech and commit messages.
    var amountLabel: String {
        if let durationSeconds { return WorkoutSet.spokenDuration(durationSeconds) }
        if let reps { return "\(reps) reps" }
        return "1 set"
    }

    static func spokenDuration(_ s: Int) -> String {
        if s >= 60 && s % 60 == 0 {
            let m = s / 60
            return m == 1 ? "one minute" : "\(m) minutes"
        }
        if s > 60 { return "\(s / 60) minute\(s / 60 == 1 ? "" : "s") \(s % 60) seconds" }
        return "\(s) seconds"
    }

    static func isoNow() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: Date())
    }
}

enum SetMode: Equatable {
    case timed(seconds: Int)
    case reps(target: Int?)
}

struct ExercisePlan: Equatable {
    var name: String
    var mode: SetMode
    var setsRemaining: Int
    var setsDone: Int = 0

    /// "30 seconds of Planks" / "12 Push-Ups" / "Push-Ups"
    var spoken: String {
        switch mode {
        case .timed(let s): return "\(WorkoutSet.spokenDuration(s)) of \(name)"
        case .reps(let t?): return "\(t) \(name)"
        case .reps(nil): return name
        }
    }

    var shortLabel: String {
        switch mode {
        case .timed(let s): return "\(s)s"
        case .reps(let t?): return "\(t) reps"
        case .reps(nil): return "reps"
        }
    }
}

/// What the user meant. Produced by the rule parser or by Claude.
enum Intent: Equatable {
    case plan(exercise: String?, reps: Int?, seconds: Int?, sets: Int?)
    case go
    case done(reps: Int?)
    case moreSets(Int)
    case stop
    case rest(seconds: Int?)
    case endSession
    case setTime(seconds: Int)
    case number(Int)
    /// A question that needs an answer (rules can't answer; Claude can).
    case question(String)
    /// Something Max should say back, already written.
    case reply(String)
    /// "Start the ab workout": run the guided circuit.
    case startRoutine
    /// Skip to the next move of the circuit.
    case next
    case unknown
}

struct FormFeedback: Codable, Equatable {
    var summary: String
    var cues: [String]
    var improvements: [String]
}

// MARK: - Six-pack focus

struct QuickPick {
    let name: String
    let label: String
    let mode: SetMode
}

/// The app's default focus: abs. A guided circuit plus one-tap ab moves.
enum AbsProgram {
    static let title = "Six-Pack Circuit"

    static let steps: [ExercisePlan] = [
        ExercisePlan(name: "Planks", mode: .timed(seconds: 30), setsRemaining: 3),
        ExercisePlan(name: "Crunches", mode: .reps(target: 20), setsRemaining: 3),
        ExercisePlan(name: "Leg Raises", mode: .reps(target: 15), setsRemaining: 3),
        ExercisePlan(name: "Bicycle Crunches", mode: .reps(target: 20), setsRemaining: 3),
        ExercisePlan(name: "Russian Twists", mode: .reps(target: 20), setsRemaining: 3),
        ExercisePlan(name: "Mountain Climbers", mode: .timed(seconds: 30), setsRemaining: 3),
    ]

    static let quickPicks: [QuickPick] = [
        QuickPick(name: "Planks", label: "Planks · 30s", mode: .timed(seconds: 30)),
        QuickPick(name: "Crunches", label: "Crunches · 20", mode: .reps(target: 20)),
        QuickPick(name: "Leg Raises", label: "Leg Raises · 15", mode: .reps(target: 15)),
        QuickPick(name: "Bicycle Crunches", label: "Bicycles · 20", mode: .reps(target: 20)),
        QuickPick(name: "Russian Twists", label: "Russian Twists · 20", mode: .reps(target: 20)),
        QuickPick(name: "Mountain Climbers", label: "Mountain Climbers · 30s", mode: .timed(seconds: 30)),
        QuickPick(name: "Dead Bug", label: "Dead Bug · 12", mode: .reps(target: 12)),
        QuickPick(name: "Hollow Hold", label: "Hollow Hold · 20s", mode: .timed(seconds: 20)),
        QuickPick(name: "Reverse Crunches", label: "Reverse Crunch · 15", mode: .reps(target: 15)),
        QuickPick(name: "Side Plank", label: "Side Plank · 20s", mode: .timed(seconds: 20)),
    ]
}
