import SwiftUI

struct LogView: View {
    @EnvironmentObject var engine: TrainerEngine
    @Environment(\.dismiss) private var dismiss

    private var store: WorkoutLogStore { engine.store }

    var body: some View {
        NavigationStack {
            List {
                if !store.pending.isEmpty || store.lastSyncError != nil {
                    Section {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(store.pending.count) set\(store.pending.count == 1 ? "" : "s") waiting to sync").font(.brand(.subheadline, .semibold))
                                if let err = store.lastSyncError { Text(err).font(.brand(.caption)).foregroundStyle(.red) }
                                else if !AppSettings.shared.hasGitHub { Text("Add a GitHub token in Settings").font(.brand(.caption)).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Button(store.isSyncing ? "Syncing…" : "Sync now") { Task { await store.sync() } }
                                .buttonStyle(.borderedProminent).disabled(store.isSyncing || !AppSettings.shared.hasGitHub)
                        }
                    }
                }
                if let err = store.lastClipError {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(store.pendingClips.count) set \(store.pendingClips.count == 1 ? "video" : "videos") waiting to upload").font(.brand(.subheadline, .semibold))
                            Text(store.clipErrorDetail ?? err).font(.brand(.caption)).foregroundStyle(.red)
                            Button("Retry upload") { Task { await store.flush() } }
                                .buttonStyle(.borderedProminent).disabled(store.isUploading)
                        }
                    }
                }
                ForEach(grouped, id: \.day) { group in
                    Section(group.day) {
                        ForEach(group.sets) { set in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(set.exercise).font(.brand(.body, .semibold))
                                    Spacer()
                                    Text(set.amountLabel).foregroundStyle(Color.accent).font(.brand(.body, .semibold))
                                    Image(systemName: set.synced ? "checkmark.icloud.fill" : "icloud.slash")
                                        .foregroundStyle(set.synced ? .green : .secondary).font(.caption)
                                    if set.video != nil {
                                        Image(systemName: "film.fill").foregroundStyle(.green).font(.caption)
                                    } else if set.clipFile != nil {
                                        Image(systemName: "arrow.up.circle").foregroundStyle(.secondary).font(.caption)
                                    }
                                }
                                if let s = set.summary, !s.isEmpty, !s.hasPrefix(set.exercise + ":") {
                                    Text(s).font(.brand(.caption)).foregroundStyle(.secondary)
                                }
                                if let tip = set.improvements.first {
                                    Text("🔧 " + tip).font(.brand(.caption)).foregroundStyle(.secondary)
                                }
                                Text(timeLabel(set.timestamp)).font(.brand(.caption2)).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                if store.sets.isEmpty {
                    Text("No sets logged yet.").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Workout log")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) { Link("Dashboard", destination: AppSettings.shared.dashboardURL) }
            }
        }
    }

    private struct DayGroup { let day: String; let sets: [WorkoutSet] }

    private var grouped: [DayGroup] {
        var order: [String] = []
        var map: [String: [WorkoutSet]] = [:]
        for set in store.sets.reversed() {
            let key = dayLabel(set.timestamp)
            if map[key] == nil { order.append(key) }
            map[key, default: []].append(set)
        }
        return order.map { DayGroup(day: $0, sets: map[$0]!) }
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private func dayLabel(_ ts: String) -> String {
        guard let d = Self.iso.date(from: ts) else { return ts }
        return d.formatted(date: .complete, time: .omitted)
    }

    private func timeLabel(_ ts: String) -> String {
        guard let d = Self.iso.date(from: ts) else { return ts }
        return d.formatted(date: .omitted, time: .shortened)
    }
}
