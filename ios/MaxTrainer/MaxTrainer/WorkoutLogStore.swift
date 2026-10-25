import Foundation
import Combine

/// Every set ever logged on this phone. Pushes unsynced sets into the dashboard's JSON file and uploads each
/// set's recorded clip to the private media repo.
@MainActor
final class WorkoutLogStore: ObservableObject {
    @Published private(set) var sets: [WorkoutSet] = []
    @Published var isSyncing = false
    @Published var isUploading = false
    @Published var lastSyncError: String?
    @Published var lastClipError: String?
    /// When the last clip upload failed, so a retry that fails again is visibly a new attempt.
    @Published var lastClipAttempt: Date?
    @Published var lastSyncDate: Date?

    private let settings = AppSettings.shared
    private let fileURL: URL
    private var syncAgain = false
    private var uploadAgain = false
    private static let maxPendingClips = 40

    /// Tests pass a disposable folder; the app uses its Documents folder.
    init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = dir.appendingPathComponent("sets.json")
        load()
        ClipStorage.pruneOrphans(keeping: Set(sets.compactMap(\.clipFile)))
    }

    var pending: [WorkoutSet] { sets.filter { !$0.synced } }
    /// Sets whose clip is recorded but not uploaded yet.
    var pendingClips: [WorkoutSet] { sets.filter { $0.video == nil && $0.clipFile != nil } }

    /// Why the last clip upload failed and when it was tried. Shown on the main screen and in the Log.
    var clipErrorDetail: String? {
        guard let err = lastClipError else { return nil }
        guard let at = lastClipAttempt else { return err }
        return "\(err)\nLast tried \(at.formatted(date: .omitted, time: .standard))."
    }

    func append(_ set: WorkoutSet) {
        sets.append(set)
        save()
    }

    func update(_ set: WorkoutSet) {
        if let i = sets.firstIndex(where: { $0.id == set.id }) {
            // Never lose a video or clip that was attached while the caller held an older copy.
            var merged = set
            if merged.video == nil { merged.video = sets[i].video }
            if merged.clipFile == nil { merged.clipFile = sets[i].clipFile }
            sets[i] = merged
            save()
        }
    }

    func clearLocal() {
        for s in sets { if let n = s.clipFile { ClipStorage.remove(n) } }
        sets = []
        save()
    }

    // MARK: - Clips

    /// A finished recording belongs to this set and waits for upload.
    func attachLocalClip(setID: String, fileName: String) {
        guard let i = sets.firstIndex(where: { $0.id == setID }) else {
            ClipStorage.remove(fileName)
            return
        }
        sets[i].clipFile = fileName
        save()
        trimPendingClips()
    }

    /// Keeps at most `maxPendingClips` unsent clips on the phone; the oldest are dropped (they are still in Photos).
    private func trimPendingClips() {
        let extra = pendingClips.count - Self.maxPendingClips
        guard extra > 0 else { return }
        for id in pendingClips.prefix(extra).map(\.id) {
            if let i = sets.firstIndex(where: { $0.id == id }), let n = sets[i].clipFile {
                ClipStorage.remove(n)
                sets[i].clipFile = nil
            }
        }
        save()
    }

    /// Uploads every waiting clip, then pushes the log. Safe to call often.
    func flush() async {
        await uploadPendingClips()
        await sync()
    }

    func uploadPendingClips() async {
        guard settings.uploadClips, settings.hasGitHub else { return }
        if isUploading { uploadAgain = true; return }
        isUploading = true
        defer { isUploading = false }
        repeat {
            uploadAgain = false
            for id in pendingClips.map(\.id) {
                guard let i = sets.firstIndex(where: { $0.id == id }), let name = sets[i].clipFile else { continue }
                guard ClipStorage.exists(name) else {
                    sets[i].clipFile = nil
                    save()
                    continue
                }
                do {
                    let info = try await MediaService(settings: settings).upload(fileURL: ClipStorage.url(for: name),
                                                                                  path: MediaService.path(for: sets[i]))
                    if let j = sets.firstIndex(where: { $0.id == id }) {
                        sets[j].video = info
                        sets[j].clipFile = nil
                        sets[j].synced = false      // the log entry now needs its video link
                        save()
                    }
                    ClipStorage.remove(name)
                    lastClipError = nil
                } catch {
                    lastClipError = error.localizedDescription
                    lastClipAttempt = Date()
                    return                         // the same problem would hit the next clip; try again later
                }
            }
        } while uploadAgain
    }

    // MARK: - Dashboard log

    /// Pushes every unsynced set into data/workouts.json. A set that is already there only gets its new fields merged in.
    @discardableResult
    func sync() async -> Bool {
        guard settings.hasGitHub else { return false }
        if isSyncing { syncAgain = true; return false }
        isSyncing = true
        defer { isSyncing = false }
        var ok = true
        repeat {
            syncAgain = false
            ok = await syncOnce()
        } while syncAgain && ok
        return ok
    }

    private func syncOnce() async -> Bool {
        let batch = pending
        guard !batch.isEmpty else { return true }
        let videoAtStart = Dictionary(uniqueKeysWithValues: batch.map { ($0.id, $0.video?.path ?? "") })
        do {
            let gh = GitHubService(settings: settings)
            var remote = try await gh.fetch()
            var list = remote.json["workouts"] as? [[String: Any]] ?? []
            var added: [WorkoutSet] = [], updated: [WorkoutSet] = []
            for s in batch {
                let key = "\(s.timestamp)|\(s.exercise)"
                if let i = list.firstIndex(where: { "\($0["timestamp"] ?? "")|\($0["exercise"] ?? "")" == key }) {
                    var e = list[i]
                    var changed = false
                    if let v = s.video, ((e["video"] as? [String: Any])?["path"] as? String) != v.path {
                        e["video"] = v.json
                        changed = true
                    }
                    if (e["cues"] as? [Any] ?? []).isEmpty, !s.cues.isEmpty { e["cues"] = s.cues; changed = true }
                    if (e["improvements"] as? [Any] ?? []).isEmpty, !s.improvements.isEmpty { e["improvements"] = s.improvements; changed = true }
                    if changed { list[i] = e; updated.append(s) }
                } else {
                    list.append(s.remoteJSON)
                    added.append(s)
                }
            }
            if !added.isEmpty || !updated.isEmpty {
                remote.json["workouts"] = list
                try await gh.put(remote, message: Self.commitMessage(added: added, updated: updated))
            }
            // A video attached while we were talking to GitHub still needs its own push.
            for i in sets.indices {
                if let was = videoAtStart[sets[i].id], was == (sets[i].video?.path ?? "") { sets[i].synced = true }
            }
            save()
            lastSyncDate = Date()
            lastSyncError = nil
            return true
        } catch {
            lastSyncError = error.localizedDescription
            return false
        }
    }

    static func commitMessage(added: [WorkoutSet], updated: [WorkoutSet]) -> String {
        if updated.isEmpty {
            if added.count == 1, let s = added.first { return "Log set: \(s.exercise) — \(s.amountLabel)" }
            let names = Array(Set(added.map(\.exercise))).sorted().joined(separator: ", ")
            return "Log \(added.count) sets: \(names)"
        }
        if added.isEmpty {
            if updated.count == 1, let s = updated.first { return "Add video: \(s.exercise) set \(s.setNumber ?? 1)" }
            return "Add video to \(updated.count) sets"
        }
        return "Log \(added.count) sets, update \(updated.count)"
    }

    // MARK: - Storage

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
