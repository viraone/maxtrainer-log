import Foundation
import Combine

/// Every set ever logged on this phone, plus pushing the unsynced ones to the dashboard's JSON file.
@MainActor
final class WorkoutLogStore: ObservableObject {
    @Published private(set) var sets: [WorkoutSet] = []
    @Published var isSyncing = false
    @Published var lastSyncError: String?
    @Published var lastSyncDate: Date?

    private let settings = AppSettings.shared
    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("sets.json")
    }()

    init() { load() }

    var pending: [WorkoutSet] { sets.filter { !$0.synced } }

    func append(_ set: WorkoutSet) {
        sets.append(set)
        save()
    }

    func update(_ set: WorkoutSet) {
        if let i = sets.firstIndex(where: { $0.id == set.id }) {
            sets[i] = set
            save()
        }
    }

    func clearLocal() {
        sets = []
        save()
    }

    /// Push every unsynced set into data/workouts.json as one commit.
    @discardableResult
    func sync() async -> Bool {
        guard settings.hasGitHub else { return false }
        guard !isSyncing else { return false }
        let batch = pending
        guard !batch.isEmpty else { return true }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let gh = GitHubService(settings: settings)
            var remote = try await gh.fetch()
            var list = remote.json["workouts"] as? [[String: Any]] ?? []
            let existing = Set(list.map { "\($0["timestamp"] ?? "")|\($0["exercise"] ?? "")" })
            for s in batch where !existing.contains("\(s.timestamp)|\(s.exercise)") {
                list.append(s.remoteJSON)
            }
            remote.json["workouts"] = list
            let message: String
            if batch.count == 1, let s = batch.first {
                message = "Log set: \(s.exercise) — \(s.amountLabel)"
            } else {
                let names = Array(Set(batch.map(\.exercise))).sorted().joined(separator: ", ")
                message = "Log \(batch.count) sets: \(names)"
            }
            try await gh.put(remote, message: message)
            let ids = Set(batch.map(\.id))
            for i in sets.indices where ids.contains(sets[i].id) { sets[i].synced = true }
            save()
            lastSyncDate = Date()
            lastSyncError = nil
            return true
        } catch {
            lastSyncError = error.localizedDescription
            return false
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([WorkoutSet].self, from: data) else { return }
        sets = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(sets) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
