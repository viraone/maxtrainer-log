import Foundation

enum ClaudeError: LocalizedError {
    case noKey
    case http(Int, String)
    case badResponse
    case refused

    var errorDescription: String? {
        switch self {
        case .noKey: return "No Claude API key set"
        case .http(let code, let msg): return "Claude HTTP \(code): \(msg)"
        case .badResponse: return "Unexpected response from Claude"
        case .refused: return "Claude declined the request"
        }
    }
}

/// Raw Messages API client (Swift has no official Anthropic SDK).
struct ClaudeService {
    let settings: AppSettings
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    static let trainerPersona = """
    You are Max, a sharp, encouraging personal trainer who lives inside an iPhone app. The phone sits on a small tripod \
    on the floor; the user talks to you out loud while working out and hears your replies through the speaker. \
    Everything you write is spoken aloud, so keep it short, natural and specific. No markdown, no lists, no emoji. \
    The user's current goal is a visible six-pack, so favor core and ab training in what you suggest; when asked about diet, sleep or consistency, answer in one short, practical sentence.
    """

    // MARK: - Intent

    static let intentSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "action": ["type": "string", "enum": ["plan", "go", "done", "more_sets", "stop", "rest", "end_session", "set_time", "start_routine", "next", "explain", "browse", "start_workout", "chat", "unknown"]],
            "exercise": ["anyOf": [["type": "string"], ["type": "null"]]],
            "reps": ["anyOf": [["type": "integer"], ["type": "null"]]],
            "seconds": ["anyOf": [["type": "integer"], ["type": "null"]]],
            "sets": ["anyOf": [["type": "integer"], ["type": "null"]]],
            "reply": ["anyOf": [["type": "string"], ["type": "null"]]],
        ],
        "required": ["action", "exercise", "reps", "seconds", "sets", "reply"],
        "additionalProperties": false,
    ]

    func parseIntent(_ utterance: String, context: String) async throws -> Intent {
        let system = ClaudeService.trainerPersona + """

        Convert the user's latest utterance into exactly one action for the workout app.

        Current state:
        \(context)

        Actions:
        - plan: the user names an exercise and/or an amount. Fill exercise (short Title Case name such as "Planks", \
        "Push-Ups", "Barbell Curls"), reps, seconds, sets when stated; null when not. "a minute" is 60 seconds. \
        If they only change the amount of the current exercise, leave exercise null.
        - go: start the set now ("let's go", "start", "ready", "go").
        - done: the set is finished; reps = the number they report, if any.
        - more_sets: add N more sets of the current exercise (sets = N, default 1).
        - stop: stop or cancel the running timer or set.
        - rest: start a rest timer (seconds if stated).
        - end_session: finished for today.
        - start_routine: the user wants the guided ab workout ("start the ab workout", "abs", "six-pack workout", "let's do the circuit").
        - next: skip to the next exercise of the guided workout ("next", "skip this one").
        - browse: the user wants to look through exercises ("show me chest exercises", "what back moves do you have", "browse exercises"). \
        Put the muscle group in exercise (chest, shoulders, back, triceps, biceps, forearms, traps, abs, quads, hamstrings, glutes, calves, cardio, legs, arms), or null for the whole library.
        - start_workout: the user wants a guided workout for a muscle group ("start the chest workout", "back day", "let's do legs") or their own starred moves ("start my workout"). \
        Put the group in exercise, or "my" for their own moves. Abs and the six-pack circuit are start_routine instead.
        - explain: the user asks how to do a move or what it is ("how do I do bicycle crunches", "show me a dead bug",         "what's a hollow hold", "how do I do this one"). Put the move's name in exercise, or null for the current one.         The app has its own written and spoken guide, so leave reply null.
        - set_time: change the current timed set to `seconds`.
        - chat: a question or remark that deserves a spoken answer. Put the answer in reply: at most two sentences, \
        coach-like, specific to the exercise if one is in play.
        - unknown: background noise or nothing actionable.
        """
        let body: [String: Any] = [
            "max_tokens": 400,
            "system": system,
            "messages": [["role": "user", "content": utterance]],
            "output_config": ["effort": "low", "format": ["type": "json_schema", "schema": ClaudeService.intentSchema]],
        ]
        let json = try await send(body)
        guard let obj = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let action = obj["action"] as? String else { throw ClaudeError.badResponse }
        let exercise = obj["exercise"] as? String
        let reps = obj["reps"] as? Int
        let seconds = obj["seconds"] as? Int
        let sets = obj["sets"] as? Int
        let reply = obj["reply"] as? String
        switch action {
        case "plan": return .plan(exercise: exercise, reps: reps, seconds: seconds, sets: sets)
        case "go": return .go
        case "done": return .done(reps: reps)
        case "more_sets": return .moreSets(max(1, sets ?? 1))
        case "stop": return .stop
        case "rest": return .rest(seconds: seconds)
        case "end_session": return .endSession
        case "start_routine": return .startRoutine
        case "next": return .next
        case "explain": return .explain(exercise)
        case "browse":
            let g = exercise.flatMap { Muscles.named(in: IntentParser.normalize($0).split(separator: " ").map(String.init))?.id }
            return .browse(g)
        case "start_workout":
            if let e = exercise?.lowercased(), e == "my" || e.hasPrefix("my ") { return .startMine }
            if let e = exercise, let g = Muscles.named(in: IntentParser.normalize(e).split(separator: " ").map(String.init)) {
                return g.id == "abs" ? .startRoutine : .startGroup(g.id)
            }
            return .unknown
        case "set_time": return seconds.map { .setTime(seconds: $0) } ?? .unknown
        case "chat": return .reply(reply ?? "")
        default: return .unknown
        }
    }

    // MARK: - Form feedback from a frame

    static let feedbackSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "summary": ["type": "string"],
            "cues": ["type": "array", "items": ["type": "string"]],
            "improvements": ["type": "array", "items": ["type": "string"]],
        ],
        "required": ["summary", "cues", "improvements"],
        "additionalProperties": false,
    ]

    func formFeedback(frame: Data, set: WorkoutSet) async throws -> FormFeedback {
        let system = ClaudeService.trainerPersona + """

        You just watched a set. The image is one frame captured mid-set by the phone on the floor. Give feedback the \
        way a trainer standing next to them would: summary is one or two spoken sentences (what looked good, the one \
        thing to fix); cues are three short form cues for this exercise; improvements are three short, concrete \
        things to do better next set. If the person is not clearly visible, say so briefly in the summary and give \
        general cues for the exercise anyway.
        """
        let text = "Exercise: \(set.exercise). Set \(set.setNumber ?? 1): \(set.amountLabel)."
        let body: [String: Any] = [
            "max_tokens": 600,
            "system": system,
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": frame.base64EncodedString()]],
                    ["type": "text", "text": text],
                ],
            ]],
            "output_config": ["effort": "medium", "format": ["type": "json_schema", "schema": ClaudeService.feedbackSchema]],
        ]
        let json = try await send(body)
        return try JSONDecoder().decode(FormFeedback.self, from: Data(json.utf8))
    }

    // MARK: - End-of-session wrap-up

    func sessionSummary(_ sets: [WorkoutSet]) async throws -> String {
        let lines = sets.map { "- \($0.exercise): \($0.amountLabel)" }.joined(separator: "\n")
        let body: [String: Any] = [
            "max_tokens": 300,
            "system": ClaudeService.trainerPersona + "\n\nThe workout just ended. Wrap it up in two or three spoken sentences: what they did, one genuine highlight, one thing to aim for next time. Plain text.",
            "messages": [["role": "user", "content": "Sets logged today:\n\(lines)"]],
            "output_config": ["effort": "low"],
        ]
        return try await send(body)
    }

    // MARK: - Transport

    /// Sends a Messages request and returns the concatenated text blocks.
    private func send(_ partial: [String: Any]) async throws -> String {
        guard settings.hasClaude else { throw ClaudeError.noKey }
        var body = partial
        let model = settings.model.trimmingCharacters(in: .whitespaces)
        body["model"] = model

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 40
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(settings.anthropicKey.trimmingCharacters(in: .whitespaces), forHTTPHeaderField: "x-api-key")
        req.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        // Server-side refusal fallbacks: supported on the Opus / Sonnet 5.5 / Fable families only.
        if model.hasPrefix("claude-opus") || model.hasPrefix("claude-fable") || model == "claude-sonnet-5-5" {
            body["fallbacks"] = "default"
            req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw ClaudeError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0["error"] as? [String: Any] }
                .flatMap { $0["message"] as? String } ?? String(data: data, encoding: .utf8) ?? ""
            throw ClaudeError.http(http.statusCode, msg)
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ClaudeError.badResponse }
        if obj["stop_reason"] as? String == "refusal" { throw ClaudeError.refused }
        let blocks = obj["content"] as? [[String: Any]] ?? []
        let text = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined()
        guard !text.isEmpty else { throw ClaudeError.badResponse }
        return text
    }
}
