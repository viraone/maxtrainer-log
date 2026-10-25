import Foundation

/// Where recorded set clips wait until they have been uploaded.
/// Application Support, so the system never clears it the way it can clear temporary files.
enum ClipStorage {
    /// Tests point this somewhere disposable.
    static var directoryOverride: URL?

    static var directory: URL {
        let dir = directoryOverride
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("clips", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(for name: String) -> URL { directory.appendingPathComponent(name) }

    /// A fresh path for a recording that is about to start.
    static func newRecordingURL() -> URL { url(for: "recording-\(UUID().uuidString).mp4") }

    /// Renames a finished recording to "<set id>.mp4". Returns the new file name.
    static func adopt(_ recording: URL, as setID: String) -> String? {
        let name = "\(setID).mp4"
        let dest = url(for: name)
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.moveItem(at: recording, to: dest)
            return name
        } catch {
            return nil
        }
    }

    static func remove(_ name: String) {
        try? FileManager.default.removeItem(at: url(for: name))
    }

    static func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: name).path)
    }

    /// Deletes clip files that no set refers to anymore (left over from a crash), once they are a few hours old.
    static func pruneOrphans(keeping names: Set<String>) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for f in files where f.pathExtension == "mp4" && !names.contains(f.lastPathComponent) {
            let modified = (try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if Date().timeIntervalSince(modified) > 6 * 3600 { try? fm.removeItem(at: f) }
        }
    }
}
