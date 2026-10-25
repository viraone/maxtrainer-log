import Foundation

/// How to do a move, written the way Max would explain it standing next to you.
struct ExerciseGuide: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let aliases: [String]       // what people say for it, besides its name
    let group: String           // the main muscle group's id
    let also: [String]          // other groups it trains
    let equipment: String
    let muscles: String
    let setup: String
    let steps: [String]
    let cues: [String]
    let mistakes: [String]
    let symbol: String
    let defaultMode: SetMode
    let featured: Bool          // one of the group's go-to moves

    /// What Max says when you ask him how to do it.
    var spoken: String {
        let how = steps.joined(separator: " ")
        return "\(name). \(setup) \(how) Key cue: \(cues.first ?? "")"
    }

    var demoURL: URL {
        let q = "how to do \(name) proper form".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        return URL(string: "https://www.youtube.com/results?search_query=\(q)")!
    }

    var defaultLabel: String {
        switch defaultMode {
        case .timed(let s): return "\(s) seconds"
        case .reps(let r?): return "\(r) reps"
        case .reps(nil): return "a set"
        }
    }

    /// Short text for a pill on the home screen: "Incline Dumbbell Press · 10".
    var pillLabel: String {
        switch defaultMode {
        case .timed(let s): return "\(name) · \(s)s"
        case .reps(let r?): return "\(name) · \(r)"
        case .reps(nil): return name
        }
    }

    var equipmentTitle: String { ExerciseLibrary.equipmentTitle(equipment) }

    /// A plan of three sets with this move's usual amount.
    func plan(sets: Int = 3) -> ExercisePlan {
        ExercisePlan(name: name, mode: defaultMode, setsRemaining: sets)
    }
}

/// The lookups the rest of the app uses, backed by the bundled library.
enum ExerciseGuides {
    static var all: [ExerciseGuide] { ExerciseLibrary.shared.all }

    /// Find a guide by name or nickname, forgiving plurals, case and extra words ("bicycle crunch", "a side plank").
    static func find(_ text: String) -> ExerciseGuide? { ExerciseLibrary.shared.find(text) }

    /// The guide whose name or nickname is exactly this text ("planks", "leg raise", "bench press").
    static func exactMatch(_ text: String) -> ExerciseGuide? { ExerciseLibrary.shared.exact(text) }
}
