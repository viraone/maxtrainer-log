import Foundation

enum GitHubError: LocalizedError {
    case noToken
    case http(Int, String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .noToken: return "No GitHub token set"
        case .http(let code, let msg): return "GitHub HTTP \(code): \(msg)"
        case .badResponse: return "Unexpected response from GitHub"
        }
    }
}

/// Reads and writes one file in the repo through the GitHub Contents API.
struct GitHubService {
    let settings: AppSettings

    struct RemoteFile {
        var sha: String?
        var json: [String: Any]
    }

    private var contentsURL: URL {
        let path = settings.repoPath.split(separator: "/").map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }.joined(separator: "/")
        return URL(string: "https://api.github.com/repos/\(settings.repoOwner)/\(settings.repoName)/contents/\(path)")!
    }

    private func request(_ method: String, query: [URLQueryItem] = []) throws -> URLRequest {
        guard settings.hasGitHub else { throw GitHubError.noToken }
        var comps = URLComponents(url: contentsURL, resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.timeoutInterval = 30
        req.setValue("Bearer \(settings.githubToken.trimmingCharacters(in: .whitespaces))", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.setValue("MaxTrainer-iOS", forHTTPHeaderField: "User-Agent")
        return req
    }

    /// Current file contents. A missing file comes back as an empty workouts list with no sha.
    func fetch() async throws -> RemoteFile {
        let req = try request("GET", query: [URLQueryItem(name: "ref", value: settings.repoBranch)])
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw GitHubError.badResponse }
        if http.statusCode == 404 { return RemoteFile(sha: nil, json: ["workouts": []]) }
        guard (200..<300).contains(http.statusCode) else { throw GitHubError.http(http.statusCode, errorMessage(data)) }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sha = obj["sha"] as? String,
              let encoded = obj["content"] as? String else { throw GitHubError.badResponse }
        let cleaned = encoded.replacingOccurrences(of: "\n", with: "")
        guard let raw = Data(base64Encoded: cleaned) else { throw GitHubError.badResponse }
        let json = (try? JSONSerialization.jsonObject(with: raw) as? [String: Any]) ?? ["workouts": []]
        return RemoteFile(sha: sha, json: json)
    }

    func put(_ file: RemoteFile, message: String) async throws {
        let data = try JSONSerialization.data(withJSONObject: file.json, options: [.prettyPrinted, .sortedKeys])
        var body: [String: Any] = [
            "message": message,
            "content": data.base64EncodedString(),
            "branch": settings.repoBranch,
        ]
        if let sha = file.sha { body["sha"] = sha }
        var req = try request("PUT")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (respData, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw GitHubError.badResponse }
        guard (200..<300).contains(http.statusCode) else { throw GitHubError.http(http.statusCode, errorMessage(respData)) }
    }

    private func errorMessage(_ data: Data) -> String {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any]).flatMap { $0["message"] as? String }
            ?? String(data: data, encoding: .utf8) ?? ""
    }
}
