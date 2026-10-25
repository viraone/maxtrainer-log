import Foundation

enum MediaError: LocalizedError {
    case notAllowed(Int, String)
    case http(Int, String)
    case fileMissing

    var errorDescription: String? {
        switch self {
        case .notAllowed(let code, let repo):
            return "GitHub \(code): your token can't write to \(repo). In GitHub, edit the token and add that repository with Contents: read and write."
        case .http(let code, let msg): return "GitHub HTTP \(code): \(msg)"
        case .fileMissing: return "The clip file is gone from this phone"
        }
    }
}

/// Uploads set clips into the private media repo through the GitHub Contents API (one file per clip).
/// The dashboard reads them back through the same API with the viewer's own token.
struct MediaService {
    let settings: AppSettings

    var repoFullName: String { "\(settings.repoOwner)/\(settings.mediaRepoName)" }

    /// videos/2026/10/24/20261024T195730Z-planks-set1-ab12cd.mp4
    static func path(for set: WorkoutSet) -> String {
        let ts = set.timestamp                                   // 2026-10-24T19:57:30Z
        let day = ts.prefix(10).replacingOccurrences(of: "-", with: "/")
        let compact = ts.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: ":", with: "")
        var slug = ""
        for ch in set.exercise.lowercased() {
            if ch.isLetter || ch.isNumber { slug.append(ch) } else if !slug.hasSuffix("-") { slug.append("-") }
        }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let short = set.id.lowercased().prefix(6)
        return "videos/\(day)/\(compact)-\(slug.isEmpty ? "set" : slug)-set\(set.setNumber ?? 1)-\(short).mp4"
    }

    private func contentsURL(_ path: String) -> URL {
        let escaped = path.split(separator: "/").map { String($0).addingPathComponentEscaped() }.joined(separator: "/")
        return URL(string: "\(settings.githubAPIBase)/repos/\(repoFullName)/contents/\(escaped)")!
    }

    private func request(_ url: URL, method: String) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 180
        req.setValue("Bearer \(settings.githubToken.trimmingCharacters(in: .whitespaces))", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.setValue("MaxTrainer-iOS", forHTTPHeaderField: "User-Agent")
        return req
    }

    func upload(fileURL: URL, path: String) async throws -> ClipInfo {
        guard settings.hasGitHub else { throw GitHubError.noToken }
        guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe), !data.isEmpty else { throw MediaError.fileMissing }
        let url = contentsURL(path)
        var attempt = 0
        while true {
            attempt += 1
            var req = request(url, method: "PUT")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: [
                "message": "Add clip \((path as NSString).lastPathComponent)",
                "content": data.base64EncodedString(),
            ])
            let (body, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw GitHubError.badResponse }
            switch http.statusCode {
            case 200..<300:
                return ClipInfo(path: path, bytes: data.count, repo: repoFullName)
            case 409 where attempt < 4:
                // Another commit landed at the same moment; GitHub asks us to try again.
                try await Task.sleep(for: .seconds(1.5 * Double(attempt)))
            case 422:
                // The file may already be there from an earlier attempt whose reply we never saw.
                if let size = try await existingSize(url), size == data.count {
                    return ClipInfo(path: path, bytes: data.count, repo: repoFullName)
                }
                throw MediaError.http(422, message(body))
            case 401, 403, 404:
                throw MediaError.notAllowed(http.statusCode, repoFullName)
            default:
                throw MediaError.http(http.statusCode, message(body))
            }
        }
    }

    private func existingSize(_ url: URL) async throws -> Int? {
        let (body, resp) = try await URLSession.shared.data(for: request(url, method: "GET"))
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
        return obj["size"] as? Int
    }

    private func message(_ data: Data) -> String {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any]).flatMap { $0["message"] as? String }
            ?? String(data: data, encoding: .utf8) ?? ""
    }
}

private extension String {
    func addingPathComponentEscaped() -> String {
        addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? self
    }
}
