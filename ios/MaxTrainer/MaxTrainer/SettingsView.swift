import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("sk-ant-…", text: $settings.anthropicKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Model", text: $settings.model)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Toggle("Form feedback from the camera", isOn: $settings.formFeedback)
                } header: {
                    Text("Claude")
                } footer: {
                    Text("With a key, Max understands free-form speech, answers questions and coaches your form from a mid-set frame. Without one he still runs timers, counts sets and logs everything from plain commands. Default model: \(AppSettings.defaultModel). For snappier replies try claude-haiku-5-5.")
                }

                Section {
                    SecureField("github_pat_…", text: $settings.githubToken)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Owner", text: $settings.repoOwner).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Repository", text: $settings.repoName).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("File path", text: $settings.repoPath).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Branch", text: $settings.repoBranch).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Link("Open the dashboard", destination: settings.dashboardURL)
                    Link("Create a fine-grained token (Contents: read & write)", destination: URL(string: "https://github.com/settings/personal-access-tokens/new")!)
                } header: {
                    Text("Dashboard (GitHub)")
                } footer: {
                    Text("Each logged set is committed to \(settings.repoPath) and shows up on the GitHub Pages dashboard. Sets are kept on the phone until they sync.")
                }

                Section {
                    Toggle("Max talks", isOn: $settings.voiceEnabled)
                    Toggle("Front camera", isOn: $settings.useFrontCamera)
                    Toggle("Record each set to Photos", isOn: $settings.recordSets)
                } header: {
                    Text("Voice & camera")
                } footer: {
                    Text("Recording starts on “let's go baby” and stops when the set ends. Clips are video only and land in your Photos library.")
                }

                Section("How to talk to Max") {
                    VStack(alignment: .leading, spacing: 6) {
                        tip("Let's do planks", "Picks a move. Max replies: tell me when to start recording you.")
                        tip("Let's go baby", "Starts recording and the set.")
                        tip("Start the ab workout", "Runs the six-pack circuit, move by move.")
                        tip("Next · skip", "Jumps to the next move of the circuit.")
                        tip("How do I do bicycle crunches?", "Opens the guide and Max talks you through it.")
                        tip("Planks, thirty seconds", "Sets up a timed set.")
                        tip("Three sets of ten push-ups", "Sets up rep-based sets.")
                        tip("Done · I did eight", "Ends a rep set (optionally with the count).")
                        tip("Three more sets", "Adds sets of the current exercise.")
                        tip("Stop", "Cancels the running timer.")
                        tip("Rest a minute", "Starts a rest timer.")
                        tip("That's it for today", "Wraps up and pushes the log.")
                    }
                    .font(.footnote)
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func tip(_ phrase: String, _ what: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("“\(phrase)”").fontWeight(.semibold).frame(width: 150, alignment: .leading)
            Text(what).foregroundStyle(.secondary)
        }
    }
}
