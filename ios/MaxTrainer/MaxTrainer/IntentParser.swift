import Foundation

/// Rule-based understanding of what the user said. Fast, offline, and the
/// fallback when Claude is not configured or not reachable.
enum IntentParser {
    static let numberWords: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
        "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14,
        "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20,
        "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
        "hundred": 100,
    ]

    static let fillers: Set<String> = [
        "lets", "let", "us", "do", "some", "start", "a", "an", "the", "of", "for", "and", "then", "please",
        "max", "hey", "ok", "okay", "with", "now", "each", "want", "to", "i", "we", "me", "give", "my",
        "set", "sets", "second", "seconds", "sec", "secs", "minute", "minutes", "min", "mins", "rep", "reps",
        "repetition", "repetitions", "timer", "time", "times", "round", "rounds", "next", "up", "go",
        "switch", "move", "on", "at", "in", "it", "that", "this", "is", "about", "like", "gonna", "going",
        "wanna", "um", "uh", "so", "alright", "all", "right", "put", "alexa", "siri", "another", "more",
        "by", "x", "say", "lets", "begin", "doing", "today", "first", "thing", "exercise", "workout",
    ]

    static let units: Set<String> = ["second", "seconds", "sec", "secs", "minute", "minutes", "min", "mins",
                                     "rep", "reps", "repetition", "repetitions", "set", "sets", "round", "rounds", "times"]

    // MARK: - Normalisation

    static func normalize(_ s: String) -> String {
        var t = s.lowercased()
        for (a, b) in [("let's", "lets"), ("let’s", "lets"), ("i'm", "im"), ("i’m", "im"), ("that's", "thats"),
                       ("that’s", "thats"), ("we're", "were"), ("-", " "), ("’", ""), ("'", "")] {
            t = t.replacingOccurrences(of: a, with: b)
        }
        t = t.map { $0.isLetter || $0.isNumber || $0 == " " ? String($0) : " " }.joined()
        return t.split(separator: " ").joined(separator: " ")
    }

    static func number(_ word: String) -> Int? {
        if let n = Int(word) { return n }
        if let n = numberWords[word] { return n }
        return nil
    }

    /// Combines "twenty five" / "forty five" style pairs.
    static func numberAt(_ words: [String], _ i: Int) -> (Int, Int)? {
        guard i < words.count, let n = number(words[i]) else { return nil }
        if n >= 20, n % 10 == 0, i + 1 < words.count, let m = number(words[i + 1]), m < 10, m > 0 {
            return (n + m, 2)
        }
        if n < 100, i + 1 < words.count, words[i + 1] == "hundred" { return (n * 100, 2) }
        return (n, 1)
    }

    // MARK: - Fast path (checked on every partial transcript)

    static let goPhrases = ["lets go", "let go", "go", "start", "begin", "start the timer", "start timer",
                            "im ready", "ready", "go go go", "here we go", "and go", "lets do it", "lets go max"]
    static let stopPhrases = ["stop", "cancel", "hold on", "pause", "wait", "stop the timer", "stop timer",
                              "hold up", "stop stop"]
    static let donePhrases = ["done", "im done", "finished", "all done", "thats it", "thats all", "im finished",
                              "complete", "finish"]

    static func fastPath(_ raw: String) -> Intent? {
        let t = normalize(raw)
        guard !t.isEmpty else { return nil }
        func endsWith(_ list: [String]) -> Bool {
            list.contains { t == $0 || t.hasSuffix(" " + $0) }
        }
        if endsWith(goPhrases) { return .go }
        if endsWith(stopPhrases) { return .stop }
        if endsWith(donePhrases) { return .done(reps: nil) }
        return nil
    }

    // MARK: - Full parse

    static func parse(_ raw: String) -> Intent {
        let t = normalize(raw)
        guard !t.isEmpty else { return .unknown }
        let words = t.split(separator: " ").map(String.init)

        if let fp = fastPath(t) { return fp }

        // Skip to the next move of the circuit
        let nextPhrases = ["next", "skip", "next exercise", "next one", "next move", "skip it", "skip this", "skip this one", "move on", "next please"]
        if nextPhrases.contains(t) || t.hasPrefix("skip ") { return .next }

        // The default focus: abs. "abs", "six pack", "start the workout" run the guided circuit.
        let asking = ["how", "what", "why", "should", "can", "could", "is", "are", "does", "which", "when", "whats", "tell"].contains(words.first ?? "")
        let wantsCircuit = words.contains("abs")
            || (words.contains("core") && (t.contains("workout") || t.contains("circuit")))
            || t.contains("six pack") || t.contains("sixpack") || t.contains("6 pack")
            || t.contains("ab workout") || t.contains("ab circuit")
            || t.contains("start the workout") || t.contains("start workout")
            || t.contains("the circuit") || t.contains("the routine")
        if !asking && wantsCircuit { return .startRoutine }

        // End of the session
        let endPhrases = ["for today", "for the day", "end workout", "end the workout", "end session",
                          "finish workout", "wrap it up", "wrap up", "call it", "im done for", "thats it for",
                          "good workout", "end of workout", "were done", "finish up"]
        if endPhrases.contains(where: { t.contains($0) }) { return .endSession }

        // "three more sets", "one more", "another set", "again"
        if let r = t.range(of: #"\b(\w+) more (sets?|rounds?|times?|reps?)\b"#, options: .regularExpression) {
            let w = String(t[r]).split(separator: " ").first.map(String.init) ?? ""
            let n = number(w) ?? 1
            if t.contains("rep") && !t.contains("set") { return .plan(exercise: nil, reps: n, seconds: nil, sets: nil) }
            return .moreSets(n)
        }
        if t.contains("another set") || t.contains("one more") || t == "again" || t.contains("do it again") || t.contains("another round") {
            return .moreSets(1)
        }

        // "I did 8", "I got 12"
        if let r = t.range(of: #"\bi (did|got|made|hit) (\d+|\w+)\b"#, options: .regularExpression) {
            let last = String(t[r]).split(separator: " ").last.map(String.init) ?? ""
            if let n = number(last) { return .done(reps: n) }
        }

        // Rest
        if t.hasPrefix("rest") || t.contains("take a break") || t.contains("break for") || t.contains("rest for") || t.contains("give me a break") {
            return .rest(seconds: seconds(in: words))
        }

        // "make it 45 seconds", "change it to a minute"
        if t.contains("make it") || t.contains("change it") || t.contains("change to") || t.contains("instead") || t.contains("bump it") {
            if let s = seconds(in: words) { return .setTime(seconds: s) }
            if let n = reps(in: words) { return .plan(exercise: nil, reps: n, seconds: nil, sets: nil) }
        }

        // "How do I do bicycle crunches", "show me leg raises", "what is a dead bug", "explain this one"
        let explainLead = ["how do i do", "how do you do", "how to do", "how do i", "show me how to do", "show me", "what is a", "what is", "what are",
                           "whats a", "whats", "explain", "demo", "demonstrate", "teach me", "how should i do", "how do we do", "how does"]
        for lead in explainLead where t == lead || t.hasPrefix(lead + " ") {
            var rest = String(t.dropFirst(lead.count)).trimmingCharacters(in: .whitespaces)
            for junk in ["a ", "an ", "the ", "some "] where rest.hasPrefix(junk) { rest = String(rest.dropFirst(junk.count)) }
            for tail in [" work", " look like", " properly", " correctly", " right", " again", " please", " max"] where rest.hasSuffix(tail) { rest = String(rest.dropLast(tail.count)) }
            if ["this", "this one", "it", "that", "that one", "this move", "this exercise", ""].contains(rest) { return .explain(nil) }
            if ExerciseGuides.find(rest) != nil { return .explain(rest) }
            break
        }

        // Questions
        let questionStarts = ["how", "what", "why", "should", "can", "could", "is", "are", "do", "does", "which", "when", "any", "whats", "tell me"]
        let planningVerbs = ["do", "start", "begin"]
        if let first = words.first, questionStarts.contains(first), !(planningVerbs.contains(first) && hasAmount(words)) {
            if !(first == "do" && words.count <= 4) { return .question(raw) }
        }

        // A workout plan: exercise + amounts
        let secs = seconds(in: words)
        let repCount = reps(in: words)
        let setCount = sets(in: words)
        let exercise = exerciseName(words)

        let planVerbs = ["lets do", "lets start", "lets go with", "do some", "start with", "switch to", "move to",
                         "next is", "next up", "time for", "give me", "now do", "lets try", "ready for", "set up", "set a timer"]
        let looksLikePlan = secs != nil || repCount != nil || setCount != nil || planVerbs.contains { t.contains($0) }

        if looksLikePlan {
            if exercise == nil && secs == nil && repCount == nil, let setCount {
                return .moreSets(setCount)
            }
            return .plan(exercise: exercise, reps: repCount, seconds: secs, sets: setCount)
        }

        // Bare number ("eight", "12")
        if words.count <= 2, let (n, used) = numberAt(words, 0), used == words.count { return .number(n) }

        // Two or three plain words with nothing else: probably an exercise name.
        if let exercise, words.count <= 3 { return .plan(exercise: exercise, reps: nil, seconds: nil, sets: nil) }

        return .unknown
    }

    // MARK: - Pieces

    static func hasAmount(_ words: [String]) -> Bool {
        seconds(in: words) != nil || reps(in: words) != nil || sets(in: words) != nil
    }

    /// Seconds mentioned: "30 seconds", "a minute", "a minute and a half", "two minutes", "half a minute".
    static func seconds(in words: [String]) -> Int? {
        let t = words.joined(separator: " ")
        if t.contains("minute and a half") || t.contains("minute thirty") { return 90 }
        if t.contains("half a minute") || t.contains("half minute") { return 30 }
        if t.contains("a minute") || t.contains("one minute") { return 60 }
        var i = 0
        while i < words.count {
            if let (n, used) = numberAt(words, i), i + used < words.count {
                let unit = words[i + used]
                if ["second", "seconds", "sec", "secs"].contains(unit) { return n }
                if ["minute", "minutes", "min", "mins"].contains(unit) {
                    if i + used + 3 < words.count, words[i + used + 1] == "and", words[i + used + 2] == "a", words[i + used + 3] == "half" {
                        return n * 60 + 30
                    }
                    return n * 60
                }
                i += used
            } else {
                i += 1
            }
        }
        return nil
    }

    /// Reps mentioned: "10 reps", "12 push-ups" (number directly before a non-unit word), "10 times".
    static func reps(in words: [String]) -> Int? {
        var i = 0
        var fallback: Int?
        while i < words.count {
            if let (n, used) = numberAt(words, i) {
                let next = i + used < words.count ? words[i + used] : ""
                if ["rep", "reps", "repetition", "repetitions", "times"].contains(next) { return n }
                if next == "of" || next == "each" {
                    // "3 sets of 10" → the number after "of" is reps
                    if next == "of", i + used + 1 < words.count, let (m, _) = numberAt(words, i + used + 1) {
                        let after = i + used + 2 < words.count ? words[i + used + 2] : ""
                        if !["second", "seconds", "sec", "secs", "minute", "minutes", "min", "mins"].contains(after) { return m }
                    }
                    if next == "each" { return n }
                }
                if !units.contains(next), !next.isEmpty, !["second", "seconds", "minute", "minutes", "sec", "secs", "min", "mins", "set", "sets", "round", "rounds", "and", "a", "of"].contains(next), fallback == nil {
                    fallback = n
                }
                if next.isEmpty, words.count > 1, fallback == nil, sets(in: words) == nil, seconds(in: words) == nil {
                    fallback = n // "push ups 12"
                }
                i += used
            } else {
                i += 1
            }
        }
        return fallback
    }

    /// Sets mentioned: "3 sets", "four rounds".
    static func sets(in words: [String]) -> Int? {
        var i = 0
        while i < words.count {
            if let (n, used) = numberAt(words, i), i + used < words.count,
               ["set", "sets", "round", "rounds"].contains(words[i + used]) {
                return n
            }
            i += 1
        }
        return nil
    }

    /// Whatever is left after removing numbers, units and filler, in Title Case.
    static func exerciseName(_ words: [String]) -> String? {
        var kept: [String] = []
        var i = 0
        while i < words.count {
            if let (_, used) = numberAt(words, i) { i += used; continue }
            let w = words[i]
            if !fillers.contains(w) && !units.contains(w) && w != "half" { kept.append(w) }
            i += 1
        }
        guard !kept.isEmpty else { return nil }
        return titleCase(kept.joined(separator: " "))
    }

    static func titleCase(_ s: String) -> String {
        let fixes: [String: String] = ["pushups": "Push-Ups", "push ups": "Push-Ups", "situps": "Sit-Ups", "sit ups": "Sit-Ups",
                                       "pullups": "Pull-Ups", "pull ups": "Pull-Ups", "plank": "Planks", "squat": "Squats",
                                       "lunge": "Lunges", "burpee": "Burpees", "crunch": "Crunches", "curl": "Curls"]
        if let f = fixes[s] { return f }
        return s.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}
