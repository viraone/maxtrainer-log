import SwiftUI

/// "How do I do this?" — a guide sheet for one move, with a Start button.
struct ExerciseGuideView: View {
    let guide: ExerciseGuide
    /// Called when Start is tapped, so a screen that opened this one (the library) can close too.
    var onStart: (() -> Void)? = nil
    @EnvironmentObject var engine: TrainerEngine
    @ObservedObject private var mine = MyMoves.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showDemo = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .center, spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.accent.opacity(0.18))
                                .frame(width: 72, height: 72)
                            Image(systemName: guide.symbol)
                                .font(.system(size: 34, weight: .semibold))
                                .foregroundStyle(Color.accent)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(guide.name).font(.brand(.title, .heavy))
                            Text(guide.muscles).font(.brand(.subheadline)).foregroundStyle(.secondary)
                            Text("\(Muscles.title(guide.group)) · \(guide.equipmentTitle)")
                                .font(.brand(.caption, .bold)).foregroundStyle(Color.accent)
                        }
                    }

                    section("Set up") {
                        Text(guide.setup)
                    }
                    section("How to do it") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(guide.steps.enumerated()), id: \.offset) { i, step in
                                HStack(alignment: .top, spacing: 10) {
                                    Text("\(i + 1)")
                                        .font(.brand(.caption, .black))
                                        .frame(width: 22, height: 22)
                                        .background(Circle().fill(Color.accent))
                                        .foregroundStyle(.black)
                                    Text(step)
                                }
                            }
                        }
                    }
                    section("Max's cues") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(guide.cues, id: \.self) { c in
                                Label(c, systemImage: "checkmark.circle.fill").foregroundStyle(.primary)
                                    .labelStyle(.titleAndIcon)
                                    .symbolRenderingMode(.hierarchical)
                                    .tint(.green)
                            }
                        }
                    }
                    section("Common mistakes") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(guide.mistakes, id: \.self) { m in
                                Label(m, systemImage: "xmark.circle.fill").foregroundStyle(.primary)
                                    .labelStyle(.titleAndIcon)
                                    .tint(.red)
                            }
                        }
                    }

                    VStack(spacing: 10) {
                        Button {
                            dismiss()
                            onStart?()
                            Task { await engine.choose(guide.name, mode: guide.defaultMode) }
                        } label: {
                            Text("Start · 3 sets of \(guide.defaultLabel)")
                                .font(.brand(.headline, .black)).frame(maxWidth: .infinity).padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent).tint(Color.accent)

                        HStack(spacing: 10) {
                            Button {
                                Task { await engine.say(guide.spoken) }
                            } label: {
                                Label("Hear it from Max", systemImage: "speaker.wave.2.fill")
                                    .font(.brand(.subheadline, .semibold)).frame(maxWidth: .infinity).padding(.vertical, 4)
                            }
                            .buttonStyle(.bordered)

                            Button { showDemo = true } label: {
                                Label("Watch a demo", systemImage: "play.rectangle.fill")
                                    .font(.brand(.subheadline, .semibold)).frame(maxWidth: .infinity).padding(.vertical, 4)
                            }
                            .buttonStyle(.bordered)
                        }
                        Text("Demo videos open right here, inside the app.")
                            .font(.brand(.caption2)).foregroundStyle(.tertiary)
                    }
                    .padding(.top, 6)
                }
                .padding(20)
            }
            .navigationTitle("How to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { mine.toggle(guide.name) } label: {
                        Image(systemName: mine.contains(guide.name) ? "star.fill" : "star")
                            .foregroundStyle(mine.contains(guide.name) ? Color.accent : Color.secondary)
                    }
                    .accessibilityLabel(mine.contains(guide.name) ? "Remove from your moves" : "Add to your moves")
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .alert("Your moves are full", isPresented: $mine.fullNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You can star up to \(MyMoves.limit) moves. Unstar one to make room.")
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showDemo) {
            SafariView(url: guide.demoURL).ignoresSafeArea()
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.brand(.caption, .black)).tracking(1.4).foregroundStyle(Color.accent)
            content().font(.brand(.body))
        }
    }
}
