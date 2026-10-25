import Foundation
import Combine

/// The moves the user has starred. They replace the six-pack picks on the home screen and make up "my workout".
@MainActor
final class MyMoves: ObservableObject {
    static let shared = MyMoves()
    static let limit = 12

    @Published private(set) var names: [String]
    /// Set when someone tries to star a move while the list is full, so the screen can say so.
    @Published var fullNotice = false
    private let defaults: UserDefaults
    private let storeKey = "myMoves"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        names = defaults.stringArray(forKey: storeKey) ?? []
    }

    var isFull: Bool { names.count >= Self.limit }
    func contains(_ name: String) -> Bool { names.contains(name) }

    /// Stars or unstars a move. A full list refuses a new star and raises `fullNotice`.
    func toggle(_ name: String) {
        if let i = names.firstIndex(of: name) {
            names.remove(at: i)
        } else if isFull {
            fullNotice = true
            return
        } else {
            names.append(name)
        }
        save()
    }

    /// Stars several moves at once, skipping ones already starred and anything past the limit. Returns how many were added.
    @discardableResult
    func add(_ list: [String]) -> Int {
        var added = 0
        var refused = false
        for n in list where !names.contains(n) {
            if isFull { refused = true; break }
            names.append(n)
            added += 1
        }
        if added > 0 { save() }
        if refused { fullNotice = true }
        return added
    }

    func clear() {
        names = []
        save()
    }

    /// The starred moves as guides, in the order they were starred.
    var guides: [ExerciseGuide] { names.compactMap { ExerciseGuides.exactMatch($0) } }

    private func save() { defaults.set(names, forKey: storeKey) }
}
