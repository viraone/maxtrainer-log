import Foundation
import Security
import Combine

enum Keychain {
    /// Tests set MAXTRAINER_TEST_MEMORY_KEYCHAIN=1 so secrets never touch the real keychain.
    private static let inMemory = ProcessInfo.processInfo.environment["MAXTRAINER_TEST_MEMORY_KEYCHAIN"] == "1"
    private static var memory: [String: String] = [:]

    private static func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.viraone.maxtrainer",
         kSecAttrAccount as String: key]
    }

    static func get(_ key: String) -> String? {
        if inMemory { return memory[key] }
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String, for key: String) {
        if value.isEmpty { delete(key); return }
        if inMemory { memory[key] = value; return }
        let data = Data(value.utf8)
        let q = query(key)
        let status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = q
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func delete(_ key: String) {
        if inMemory { memory[key] = nil; return }
        SecItemDelete(query(key) as CFDictionary)
    }
}

/// User-editable configuration. Secrets live in the Keychain, the rest in UserDefaults.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    @Published var anthropicKey: String { didSet { Keychain.set(anthropicKey, for: "anthropic_key") } }
    @Published var githubToken: String { didSet { Keychain.set(githubToken, for: "github_token") } }
    @Published var model: String { didSet { defaults.set(model, forKey: "model") } }
    @Published var repoOwner: String { didSet { defaults.set(repoOwner, forKey: "repoOwner") } }
    @Published var repoName: String { didSet { defaults.set(repoName, forKey: "repoName") } }
    @Published var repoPath: String { didSet { defaults.set(repoPath, forKey: "repoPath") } }
    @Published var repoBranch: String { didSet { defaults.set(repoBranch, forKey: "repoBranch") } }
    @Published var voiceEnabled: Bool { didSet { defaults.set(voiceEnabled, forKey: "voiceEnabled") } }
    @Published var useFrontCamera: Bool { didSet { defaults.set(useFrontCamera, forKey: "useFrontCamera") } }
    @Published var formFeedback: Bool { didSet { defaults.set(formFeedback, forKey: "formFeedback") } }
    @Published var recordSets: Bool { didSet { defaults.set(recordSets, forKey: "recordSets") } }
    /// AVSpeechSynthesisVoice identifier, or "" for the best installed voice.
    @Published var voiceIdentifier: String { didSet { defaults.set(voiceIdentifier, forKey: "voiceIdentifier") } }
    /// Name of the private repo (under the same owner) that holds the set videos.
    @Published var mediaRepoName: String { didSet { defaults.set(mediaRepoName, forKey: "mediaRepoName") } }
    /// Upload each recorded set to the private media repo so the dashboard can play it.
    @Published var uploadClips: Bool { didSet { defaults.set(uploadClips, forKey: "uploadClips") } }

    static let defaultModel = "claude-opus-5-5"

    private init() {
        anthropicKey = Keychain.get("anthropic_key") ?? ""
        githubToken = Keychain.get("github_token") ?? ""
        model = defaults.string(forKey: "model") ?? AppSettings.defaultModel
        repoOwner = defaults.string(forKey: "repoOwner") ?? "viraone"
        repoName = defaults.string(forKey: "repoName") ?? "maxtrainer-log"
        repoPath = defaults.string(forKey: "repoPath") ?? "data/workouts.json"
        repoBranch = defaults.string(forKey: "repoBranch") ?? "main"
        voiceEnabled = defaults.object(forKey: "voiceEnabled") as? Bool ?? true
        useFrontCamera = defaults.object(forKey: "useFrontCamera") as? Bool ?? true
        formFeedback = defaults.object(forKey: "formFeedback") as? Bool ?? true
        recordSets = defaults.object(forKey: "recordSets") as? Bool ?? true
        voiceIdentifier = defaults.string(forKey: "voiceIdentifier") ?? ""
        mediaRepoName = defaults.string(forKey: "mediaRepoName") ?? "maxtrainer-media"
        uploadClips = defaults.object(forKey: "uploadClips") as? Bool ?? true
    }

    var hasClaude: Bool { !anthropicKey.trimmingCharacters(in: .whitespaces).isEmpty }
    var hasGitHub: Bool { !githubToken.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Only tests change this (a hidden defaults key) to talk to a local fake GitHub.
    var githubAPIBase: String { defaults.string(forKey: "githubAPIBase") ?? "https://api.github.com" }

    var dashboardURL: URL {
        URL(string: "https://\(repoOwner).github.io/\(repoName)/")!
    }
}
