import SwiftUI

/// Browse every move by muscle group, search them, and star the ones that should be on your home screen.
struct ExerciseLibraryView: View {
    let request: LibraryRequest
    @EnvironmentObject var engine: TrainerEngine
    @ObservedObject private var mine = MyMoves.shared
    @Environment(\.dismiss) private var dismiss
    @State private var path: [String] = []
    @State private var query = ""
    @State private var guide: ExerciseGuide?
    @State private var applied = false

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    private var library: ExerciseLibrary { .shared }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if query.trimmingCharacters(in: .whitespaces).isEmpty { root } else { results }
            }
            .navigationTitle("Exercises")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search \(library.all.count) exercises")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .navigationDestination(for: String.self) { id in
                GroupExercisesView(groupID: id, onOpen: { guide = $0 }, onWorkout: startWorkout(id))
            }
        }
        .sheet(item: $guide) { g in
            ExerciseGuideView(guide: g, onStart: { dismiss() }).environmentObject(engine)
        }
        .alert("Your moves are full", isPresented: $mine.fullNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You can star up to \(MyMoves.limit) moves. Unstar one to make room.")
        }
        .onAppear {
            guard !applied else { return }
            applied = true
            if let g = request.group { path = [g] }
            if let q = request.query { query = q }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func startWorkout(_ group: String) -> () -> Void {
        return {
            dismiss()
            Task { await engine.handle("start the \(group) workout") }
        }
    }

    // MARK: - Pieces

    private var root: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if !mine.names.isEmpty { yourMoves }
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Muscles.real) { g in
                        NavigationLink(value: g.id) { tile(g) }.buttonStyle(.plain)
                    }
                }
                Text("Star a move to put it on your home screen. You can also say a muscle, like “show me back exercises”.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
    }

    private func tile(_ g: MuscleGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: g.symbol).font(.system(size: 26, weight: .semibold)).foregroundStyle(Color.accent)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 2) {
                Text(g.title).font(.headline.weight(.bold))
                Text("\(library.count(in: g.id)) exercises").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.08)))
    }

    private var yourMoves: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("YOUR MOVES").font(.caption.weight(.black)).tracking(1.4).foregroundStyle(Color.accent)
                Spacer()
                Button("Clear") { mine.clear() }.font(.caption.weight(.semibold))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(mine.guides) { g in
                        Button { guide = g } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "star.fill").font(.caption2).foregroundStyle(Color.accent)
                                Text(g.name).font(.footnote.weight(.semibold))
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Capsule().fill(Color.white.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Text("These are on your home screen. “Start my workout” runs them in order.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var results: some View {
        let found = library.search(query)
        return List {
            if found.isEmpty {
                Text("Nothing matches “\(query.trimmingCharacters(in: .whitespaces))”.").foregroundStyle(.secondary)
            }
            ForEach(found) { g in ExerciseRow(guide: g, showGroup: true, onOpen: { guide = $0 }) }
        }
        .listStyle(.plain)
    }
}

/// The moves of one muscle group: top picks first, with equipment filters and a button to start a workout.
struct GroupExercisesView: View {
    let groupID: String
    let onOpen: (ExerciseGuide) -> Void
    let onWorkout: () -> Void
    @ObservedObject private var mine = MyMoves.shared
    @State private var equipment: String?

    private var everything: [ExerciseGuide] { ExerciseLibrary.shared.exercises(in: groupID) }
    private var shown: [ExerciseGuide] { equipment.map { e in everything.filter { $0.equipment == e } } ?? everything }
    private var equipmentChoices: [String] { ExerciseLibrary.equipmentOrder.filter { e in everything.contains { $0.equipment == e } } }
    private var workoutSize: Int { ExerciseLibrary.shared.workout(for: groupID).count }

    var body: some View {
        List {
            Section {
                if workoutSize > 0 && groupID != "abs" {
                    Button(action: onWorkout) {
                        Label("Start the \(Muscles.title(groupID).lowercased()) workout · \(workoutSize) moves", systemImage: "play.fill")
                            .font(.subheadline.weight(.bold)).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent).tint(Color.accent).foregroundStyle(.black)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0)).listRowBackground(Color.clear)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip("All", selected: equipment == nil) { equipment = nil }
                        ForEach(equipmentChoices, id: \.self) { e in
                            chip(ExerciseLibrary.equipmentTitle(e), selected: equipment == e) { equipment = (equipment == e ? nil : e) }
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)).listRowBackground(Color.clear)
            }
            let top = shown.filter(\.featured), more = shown.filter { !$0.featured }
            if !top.isEmpty {
                Section("Top picks") { ForEach(top) { ExerciseRow(guide: $0, onOpen: onOpen) } }
            }
            if !more.isEmpty {
                Section(top.isEmpty ? "All exercises" : "More") { ForEach(more) { ExerciseRow(guide: $0, onOpen: onOpen) } }
            }
        }
        .navigationTitle(Muscles.title(groupID))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { mine.add(ExerciseLibrary.shared.featured(in: groupID).map(\.name)) } label: {
                        Label("Star the top picks", systemImage: "star")
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.footnote.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(selected ? Color.accent : Color.white.opacity(0.12)))
                .foregroundStyle(selected ? Color.black : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

/// One move in a list: tap for the how-to, tap the star to keep it on your home screen.
struct ExerciseRow: View {
    let guide: ExerciseGuide
    var showGroup = false
    let onOpen: (ExerciseGuide) -> Void
    @ObservedObject private var mine = MyMoves.shared

    var body: some View {
        HStack(spacing: 12) {
            Button { onOpen(guide) } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(guide.name).font(.body.weight(.semibold)).foregroundStyle(.primary)
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button { mine.toggle(guide.name) } label: {
                Image(systemName: starred ? "star.fill" : "star")
                    .font(.title3).foregroundStyle(starred ? Color.accent : Color.secondary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(starred ? "Remove \(guide.name) from your moves" : "Add \(guide.name) to your moves")
        }
    }

    private var starred: Bool { mine.contains(guide.name) }

    private var subtitle: String {
        [showGroup ? Muscles.title(guide.group) : nil, guide.equipmentTitle, guide.defaultLabel].compactMap { $0 }.joined(separator: " · ")
    }
}
