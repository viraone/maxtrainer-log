import Foundation

/// A muscle group of the library. Virtual groups (legs, arms) cover several real ones.
struct MuscleGroup: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
    let words: [String]              // what people say for it
    var members: [String] = []       // virtual groups: the real groups they cover
    var isVirtual: Bool { !members.isEmpty }
}

enum Muscles {
    /// The groups shown in the library, in the order the user asked for them.
    static let real: [MuscleGroup] = [
        MuscleGroup(id: "chest", title: "Chest", symbol: "figure.strengthtraining.traditional", words: ["chest", "pecs", "pec", "pectorals"]),
        MuscleGroup(id: "shoulders", title: "Shoulders", symbol: "figure.arms.open", words: ["shoulders", "shoulder", "delts", "delt", "deltoids"]),
        MuscleGroup(id: "back", title: "Back", symbol: "figure.rower", words: ["back", "lats", "lat"]),
        MuscleGroup(id: "triceps", title: "Triceps", symbol: "figure.boxing", words: ["triceps", "tricep"]),
        MuscleGroup(id: "biceps", title: "Biceps", symbol: "dumbbell.fill", words: ["biceps", "bicep"]),
        MuscleGroup(id: "forearms", title: "Forearms", symbol: "hand.raised.fill", words: ["forearms", "forearm"]),
        MuscleGroup(id: "traps", title: "Traps", symbol: "figure.climbing", words: ["traps", "trap", "trapezius"]),
        MuscleGroup(id: "abs", title: "Abs & Core", symbol: "figure.core.training", words: ["abs", "core", "abdominals", "ab"]),
        MuscleGroup(id: "quads", title: "Quads", symbol: "figure.step.training", words: ["quads", "quad", "quadriceps", "thighs"]),
        MuscleGroup(id: "hamstrings", title: "Hamstrings", symbol: "figure.walk", words: ["hamstrings", "hamstring", "hammies"]),
        MuscleGroup(id: "glutes", title: "Glutes", symbol: "figure.cross.training", words: ["glutes", "glute", "butt", "booty"]),
        MuscleGroup(id: "calves", title: "Calves", symbol: "shoeprints.fill", words: ["calves", "calf"]),
        MuscleGroup(id: "cardio", title: "Cardio", symbol: "figure.highintensity.intervaltraining", words: ["cardio", "conditioning", "hiit"]),
    ]

    /// Names people use for several groups at once. Not shown as tiles.
    static let virtual: [MuscleGroup] = [
        MuscleGroup(id: "legs", title: "Legs", symbol: "figure.step.training", words: ["legs", "leg"], members: ["quads", "hamstrings", "glutes", "calves"]),
        MuscleGroup(id: "arms", title: "Arms", symbol: "dumbbell.fill", words: ["arms", "arm"], members: ["biceps", "triceps", "forearms"]),
    ]

    static var all: [MuscleGroup] { real + virtual }

    static func group(_ id: String) -> MuscleGroup? { all.first { $0.id == id } }
    static func title(_ id: String) -> String { group(id)?.title ?? id.capitalized }
    static func symbol(_ id: String) -> String { group(id)?.symbol ?? "figure.strengthtraining.functional" }

    /// The real groups behind an id: itself, or a virtual group's members.
    static func members(of id: String) -> [String] {
        if let g = virtual.first(where: { $0.id == id }) { return g.members }
        return [id]
    }

    /// A group named in speech: "chest", "pecs", "calves", "legs". Real groups win over virtual ones.
    static func named(in words: [String]) -> MuscleGroup? {
        for g in real where words.contains(where: { g.words.contains($0) }) { return g }
        for g in virtual where words.contains(where: { g.words.contains($0) }) { return g }
        return nil
    }
}

/// The exercise library: every move with its guide, found by name, nickname or search.
final class ExerciseLibrary {
    static let equipmentOrder = ["bodyweight", "dumbbell", "barbell", "cable", "machine", "kettlebell", "band", "other"]

    static func equipmentTitle(_ e: String) -> String {
        switch e {
        case "bodyweight": return "Bodyweight"
        case "dumbbell": return "Dumbbell"
        case "barbell": return "Barbell"
        case "cable": return "Cable"
        case "machine": return "Machine"
        case "kettlebell": return "Kettlebell"
        case "band": return "Band"
        default: return "Other"
        }
    }

    let all: [ExerciseGuide]
    private let index: [String: ExerciseGuide]                 // stemmed name or nickname -> guide
    private let searchStems: [String: (name: [String], alias: [String], other: [String])]

    init(guides: [ExerciseGuide]) {
        all = guides
        var idx: [String: ExerciseGuide] = [:]
        var stems: [String: (name: [String], alias: [String], other: [String])] = [:]
        for g in guides {
            for text in [g.name] + g.aliases {
                let k = Self.key(text)
                if !k.isEmpty, idx[k] == nil { idx[k] = g }
            }
            let words = { (s: String) in IntentParser.normalize(s).split(separator: " ").map { Self.stem(String($0)) } }
            let groupWords = ([Muscles.title(g.group)] + g.also.map(Muscles.title) + (Muscles.group(g.group)?.words ?? [])).flatMap(words)
            stems[g.id] = (words(g.name), g.aliases.flatMap(words),
                           groupWords + words(g.equipmentTitle) + words(g.muscles))
        }
        index = idx
        searchStems = stems
    }

    /// Loads a library from a JSON file. Returns nil if the file cannot be read.
    convenience init?(contentsOf url: URL) {
        guard let data = try? Data(contentsOf: url), let raws = try? JSONDecoder().decode([Raw].self, from: data) else { return nil }
        self.init(guides: raws.map(\.guide))
    }

    private struct Raw: Decodable {
        let name: String
        let aliases: [String]
        let group: String
        let also: [String]
        let equipment: String
        let mode: String
        let amount: Int
        let muscles: String
        let setup: String
        let steps: [String]
        let cues: [String]
        let mistakes: [String]
        let featured: Bool
        let symbol: String?

        var guide: ExerciseGuide {
            ExerciseGuide(name: name, aliases: aliases, group: group, also: also, equipment: equipment, muscles: muscles,
                          setup: setup, steps: steps, cues: cues, mistakes: mistakes,
                          symbol: symbol ?? Muscles.symbol(group),
                          defaultMode: mode == "timed" ? .timed(seconds: amount) : .reps(target: amount),
                          featured: featured)
        }
    }

    /// The library bundled with the app.
    static let shared: ExerciseLibrary = {
        if let url = Bundle.main.url(forResource: "exercises", withExtension: "json"), let lib = ExerciseLibrary(contentsOf: url) { return lib }
        return ExerciseLibrary(guides: [])
    }()

    // MARK: - Browsing

    /// Every move of a group (or of a virtual group's members). The top picks come first, best move first, then the rest A to Z.
    func exercises(in group: String) -> [ExerciseGuide] {
        let ids = Set(Muscles.members(of: group))
        let inGroup = all.filter { ids.contains($0.group) }
        return inGroup.filter(\.featured) + inGroup.filter { !$0.featured }.sorted { $0.name < $1.name }
    }

    func count(in group: String) -> Int {
        let ids = Set(Muscles.members(of: group))
        return all.filter { ids.contains($0.group) }.count
    }

    /// The go-to moves of a group, in the order they were written (big lifts first).
    func featured(in group: String, limit: Int = 6) -> [ExerciseGuide] {
        let ids = Muscles.members(of: group)
        if ids.count == 1 { return Array(all.filter { $0.group == ids[0] && $0.featured }.prefix(limit)) }
        // A virtual group takes its picks from every member in turn, so a leg day hits quads, hamstrings and glutes.
        let lists = ids.map { id in all.filter { $0.group == id && $0.featured } }
        var out: [ExerciseGuide] = []
        var round = 0
        while out.count < limit, lists.contains(where: { round < $0.count }) {
            for l in lists where round < l.count && out.count < limit { out.append(l[round]) }
            round += 1
        }
        return out
    }

    /// The moves of a guided workout for a group: five go-to moves, three sets each.
    func workout(for group: String) -> [ExercisePlan] {
        featured(in: group, limit: 5).map { $0.plan() }
    }

    // MARK: - Finding by name

    /// Singular, lowercase stem of a word, the same for "raise" and "raises", "press" and "presses", "lunge" and "lunges".
    static func stem(_ word: String) -> String {
        var w = word.lowercased()
        let irregular = ["calves": "calf", "feet": "foot"]
        if let r = irregular[w] { return r }
        if w.count > 3 {
            if w.hasSuffix("ies") { w = String(w.dropLast(3)) + "y" }
            else if w.hasSuffix("sses") || w.hasSuffix("ches") || w.hasSuffix("shes") || w.hasSuffix("xes") || w.hasSuffix("zes") { w.removeLast(2) }
            else if w.hasSuffix("s"), !w.hasSuffix("ss"), !w.hasSuffix("us"), !w.hasSuffix("is") { w.removeLast() }
        } else if w.count == 3, w.hasSuffix("s"), !w.hasSuffix("ss"), !w.hasSuffix("us"), !w.hasSuffix("is") {
            w.removeLast()                                     // "abs" and "ab"
        }
        if w.count > 3, w.hasSuffix("e") { w.removeLast() }
        return w
    }

    static func key(_ text: String) -> String {
        IntentParser.normalize(text).split(separator: " ").map { stem(String($0)) }.joined(separator: " ")
    }

    /// The move whose name or nickname is exactly this text ("planks", "leg raise", "bench press").
    func exact(_ text: String) -> ExerciseGuide? {
        let k = Self.key(text)
        return k.isEmpty ? nil : index[k]
    }

    /// The move best matching a phrase: an exact name or nickname, else the most specific move whose
    /// name or nickname has all its words in the phrase ("how do i do the incline dumbbell press").
    func find(_ text: String) -> ExerciseGuide? {
        let wanted = Self.key(text)
        guard !wanted.isEmpty else { return nil }
        if let hit = index[wanted] { return hit }
        let words = Set(wanted.split(separator: " ").map(String.init))
        var best: (guide: ExerciseGuide, score: Int)?
        for (k, g) in index {
            let parts = k.split(separator: " ").map(String.init)
            guard parts.allSatisfy(words.contains) else { continue }
            let score = parts.count * 10 + (g.featured ? 1 : 0)
            if best == nil || score > best!.score || (score == best!.score && g.name < best!.guide.name) { best = (g, score) }
        }
        return best?.guide
    }

    // MARK: - Search

    /// Moves matching what was typed. Every word has to match the start of a word in the name, a nickname,
    /// the muscle group or the equipment ("incl db", "chest cable", "calf").
    func search(_ query: String, limit: Int = 80) -> [ExerciseGuide] {
        let tokens = IntentParser.normalize(query).split(separator: " ").map { Self.stem(String($0)) }.filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return [] }
        var scored: [(ExerciseGuide, Int)] = []
        for g in all {
            guard let s = searchStems[g.id] else { continue }
            var score = 0
            var matched = true
            for t in tokens {
                if s.name.contains(where: { $0.hasPrefix(t) }) { score += 10 }
                else if s.alias.contains(where: { $0.hasPrefix(t) }) { score += 6 }
                else if s.other.contains(where: { $0.hasPrefix(t) }) { score += 3 }
                else { matched = false; break }
            }
            if matched { scored.append((g, score + (g.featured ? 1 : 0))) }
        }
        return scored.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.name < $1.0.name }.prefix(limit).map(\.0)
    }
}
