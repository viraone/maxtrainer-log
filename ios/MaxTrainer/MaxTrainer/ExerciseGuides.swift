import Foundation

/// How to do a move, written the way Max would explain it standing next to you.
struct ExerciseGuide: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let muscles: String
    let setup: String
    let steps: [String]
    let cues: [String]
    let mistakes: [String]
    let symbol: String
    let defaultMode: SetMode

    /// What Max says when you ask him how to do it.
    var spoken: String {
        let how = steps.joined(separator: " ")
        return "\(name). \(setup) \(how) Key cue: \(cues.first ?? "")"
    }

    var demoURL: URL {
        let q = "how to do \(name) proper form".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        return URL(string: "https://www.youtube.com/results?search_query=\(q)")!
    }

    var defaultLabel: String {
        switch defaultMode {
        case .timed(let s): return "\(s) seconds"
        case .reps(let r?): return "\(r) reps"
        case .reps(nil): return "a set"
        }
    }
}

enum ExerciseGuides {
    static let all: [ExerciseGuide] = [
        ExerciseGuide(
            name: "Planks", muscles: "Deep core, obliques, shoulders",
            setup: "Forearms on the floor, elbows under your shoulders, legs straight behind you on your toes.",
            steps: ["Lift your hips so your body makes one straight line from head to heels.",
                    "Squeeze your glutes and pull your belly button toward your spine.",
                    "Breathe steadily and hold without letting the hips sag or pike up."],
            cues: ["Straight line, head to heels", "Squeeze your glutes", "Breathe, don't hold your breath"],
            mistakes: ["Hips sagging toward the floor", "Butt up in the air", "Looking up and craning the neck"],
            symbol: "figure.core.training", defaultMode: .timed(seconds: 30)),

        ExerciseGuide(
            name: "Crunches", muscles: "Upper abs",
            setup: "Lie on your back, knees bent, feet flat on the floor, fingertips lightly behind your ears.",
            steps: ["Breathe out and curl your shoulders up off the floor, chin slightly tucked.",
                    "Lift only until your shoulder blades clear the floor. Your lower back stays down.",
                    "Pause for a second at the top, then lower slowly."],
            cues: ["Curl up, don't sit up", "Exhale on the way up", "Lower slow"],
            mistakes: ["Pulling on your neck with your hands", "Yanking up with momentum", "Lifting the lower back off the floor"],
            symbol: "figure.core.training", defaultMode: .reps(target: 20)),

        ExerciseGuide(
            name: "Leg Raises", muscles: "Lower abs, hip flexors",
            setup: "Lie flat on your back, legs straight, hands under your hips or flat by your sides.",
            steps: ["Keep your legs straight and lift them together until they point at the ceiling.",
                    "Lower them slowly until they are just above the floor, without touching down.",
                    "Keep your lower back pressed into the floor the whole time."],
            cues: ["Lower back glued to the floor", "Slow on the way down", "Don't let the feet touch"],
            mistakes: ["Lower back arching off the floor", "Dropping the legs fast", "Bending the knees a lot"],
            symbol: "figure.core.training", defaultMode: .reps(target: 15)),

        ExerciseGuide(
            name: "Bicycle Crunches", muscles: "Obliques, upper and lower abs",
            setup: "Lie on your back, hands lightly behind your ears, knees up at ninety degrees, shins parallel to the floor.",
            steps: ["Bring your right elbow toward your left knee while you straighten the right leg out.",
                    "Switch sides: left elbow to right knee, left leg straight. That's like pedaling a bike.",
                    "Twist from the ribs, not the neck, and keep the pace slow and controlled. One elbow-to-knee each side is one rep."],
            cues: ["Twist from the ribs", "Slow pedal, not a sprint", "Elbows wide, chin up"],
            mistakes: ["Pulling the head with the hands", "Going so fast the abs never work", "Letting the straight leg drop to the floor"],
            symbol: "figure.core.training", defaultMode: .reps(target: 20)),

        ExerciseGuide(
            name: "Russian Twists", muscles: "Obliques",
            setup: "Sit on the floor, knees bent, lean back a little so your abs switch on. Lift your feet an inch if you can, or keep heels down to make it easier.",
            steps: ["Clasp your hands together in front of your chest.",
                    "Rotate your torso to the right and tap your hands beside your hip, then rotate to the left and tap.",
                    "Keep your chest up and move your shoulders, not just your arms. Right plus left is one rep."],
            cues: ["Chest up, lean back", "Turn the shoulders", "Tap beside the hip"],
            mistakes: ["Only swinging the arms", "Rounding the back", "Going too fast"],
            symbol: "figure.core.training", defaultMode: .reps(target: 20)),

        ExerciseGuide(
            name: "Mountain Climbers", muscles: "Lower abs, hip flexors, shoulders, plus cardio",
            setup: "Start in a high plank: hands under shoulders, arms straight, body in one line.",
            steps: ["Drive your right knee toward your chest, then shoot it back as the left knee comes in.",
                    "Keep switching, like running in place with your hands on the floor.",
                    "Hips stay level with your shoulders. Don't let them bounce up."],
            cues: ["Hips low and level", "Knee to chest", "Hands stay under shoulders"],
            mistakes: ["Hips piking up", "Shoulders drifting behind the hands", "Short, lazy knee drives"],
            symbol: "figure.highintensity.intervaltraining", defaultMode: .timed(seconds: 30)),

        ExerciseGuide(
            name: "Dead Bug", muscles: "Deep core, lower abs",
            setup: "Lie on your back with arms straight up toward the ceiling and knees bent at ninety degrees over your hips.",
            steps: ["Breathe out and press your lower back flat into the floor.",
                    "Slowly lower your right arm overhead and straighten your left leg toward the floor at the same time.",
                    "Come back to the start and switch sides. Left arm, right leg. One each side is one rep."],
            cues: ["Lower back flat the whole time", "Opposite arm and leg", "Slow and steady"],
            mistakes: ["Lower back arching", "Moving fast", "Holding your breath"],
            symbol: "figure.core.training", defaultMode: .reps(target: 12)),

        ExerciseGuide(
            name: "Hollow Hold", muscles: "Whole front of the core",
            setup: "Lie on your back, arms straight overhead, legs straight and together.",
            steps: ["Press your lower back into the floor and lift your shoulders and legs a few inches off the ground.",
                    "Your body makes a shallow banana shape. Arms by your ears, toes pointed.",
                    "Hold it. If your back lifts, raise the legs higher or bend the knees to make it easier."],
            cues: ["Banana shape", "Lower back pressed down", "Keep breathing"],
            mistakes: ["Lower back arching off the floor", "Chin jammed into the chest", "Legs too low, too soon"],
            symbol: "figure.core.training", defaultMode: .timed(seconds: 20)),

        ExerciseGuide(
            name: "Reverse Crunches", muscles: "Lower abs",
            setup: "Lie on your back, hands by your sides or under your hips, knees bent and feet off the floor.",
            steps: ["Breathe out and pull your knees toward your chest, curling your hips up off the floor.",
                    "Lift the hips with your abs, not by swinging the legs.",
                    "Lower the hips back down slowly and stop before your feet touch the floor."],
            cues: ["Hips curl up", "Slow on the way down", "No swinging"],
            mistakes: ["Swinging the legs for momentum", "Dropping the hips", "Using the hands to push"],
            symbol: "figure.core.training", defaultMode: .reps(target: 15)),

        ExerciseGuide(
            name: "Side Plank", muscles: "Obliques, hips",
            setup: "Lie on your side, forearm on the floor with the elbow under your shoulder, legs stacked.",
            steps: ["Lift your hips so your body makes a straight line from head to feet.",
                    "Stack your shoulders, hips and feet, and keep your top hand on your hip or reaching up.",
                    "Hold, then switch sides for the next set."],
            cues: ["Hips up, straight line", "Stack everything", "Push the floor away"],
            mistakes: ["Hips sagging toward the floor", "Rolling forward or back", "Shoulder creeping up to the ear"],
            symbol: "figure.core.training", defaultMode: .timed(seconds: 20)),

        ExerciseGuide(
            name: "Push-Ups", muscles: "Chest, shoulders, triceps, core",
            setup: "Hands on the floor a bit wider than your shoulders, body in one straight line, toes on the floor.",
            steps: ["Lower your chest toward the floor, elbows tucked at about forty-five degrees.",
                    "Stop an inch above the floor, then push back up to straight arms.",
                    "Keep your core tight so the hips move with the shoulders."],
            cues: ["One straight line", "Elbows at forty-five", "Chest to the floor"],
            mistakes: ["Hips sagging", "Elbows flared wide", "Half reps"],
            symbol: "figure.strengthtraining.functional", defaultMode: .reps(target: 10)),

        ExerciseGuide(
            name: "Squats", muscles: "Quads, glutes, core",
            setup: "Feet shoulder-width apart, toes turned out a little, arms out in front.",
            steps: ["Push your hips back and bend your knees to sit down, like onto a chair.",
                    "Go until your thighs are at least parallel to the floor, chest up.",
                    "Drive through your heels to stand back up."],
            cues: ["Chest up", "Knees track over toes", "Drive through the heels"],
            mistakes: ["Knees caving in", "Heels lifting", "Rounding the back"],
            symbol: "figure.strengthtraining.functional", defaultMode: .reps(target: 15)),
    ]

    /// Find a guide by name, forgiving plurals, case and extra words ("bicycle crunch", "a side plank").
    static func find(_ text: String) -> ExerciseGuide? {
        let t = IntentParser.normalize(text)
        guard !t.isEmpty else { return nil }
        func key(_ s: String) -> String {
            IntentParser.normalize(s).split(separator: " ").map { w -> String in
                var w = String(w)
                if w.hasSuffix("es"), w.count > 4 { w.removeLast(2) } else if w.hasSuffix("s"), w.count > 3 { w.removeLast() }
                return w
            }.joined(separator: " ")
        }
        let wanted = key(t)
        if let exact = all.first(where: { key($0.name) == wanted }) { return exact }
        // Every word of the guide's name appears in what was said
        return all.first { g in
            let words = key(g.name).split(separator: " ").map(String.init)
            return words.allSatisfy { wanted.contains($0) }
        }
    }
}
