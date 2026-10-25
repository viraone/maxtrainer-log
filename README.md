# MaxTrainer

A voice-run personal trainer for iPhone, focused on abs and a six-pack, plus the workout dashboard it logs to.

- **`ios/MaxTrainer`** — the iOS app. Put the phone on a tripod, talk to Max.
- **`index.html` + `data/workouts.json`** — the dashboard, served by GitHub Pages at
  https://viraone.github.io/maxtrainer-log/. The app commits every set into `data/workouts.json`.

## Talking to Max

| You say | Max does |
| --- | --- |
| "Let's do planks" | Picks a move (default amount from its guide). Max replies "Got it. Tell me when to start recording you." |
| "Let's go baby" | Starts recording the set to Photos, counts down, and starts the timer or rep count. |
| "Start the ab workout" (or "abs", "six-pack") | Runs the six-pack circuit: planks, crunches, leg raises, bicycle crunches, Russian twists, mountain climbers, three sets each. Max moves to the next exercise by himself. |
| "Next" / "skip" | Jumps to the next move of the circuit. |
| "How do I do bicycle crunches?" | Opens the move's guide (set-up, steps, cues, mistakes, an in-app demo video) and Max talks you through it. Tapping any move on the home screen opens the same guide. |
| "Planks, thirty seconds" | Sets up a timed set. |
| "Three sets of ten push-ups" | Sets up rep-based sets. |
| "Done" / "I did eight" | Ends a rep set, with the count if you give one. |
| "Three more sets" | Adds sets of the current exercise. |
| "Stop" | Cancels the running timer. |
| "Rest a minute" | Starts a rest timer. |
| "That's it for today" | Wraps up and pushes the log to the dashboard. |
| "Show me chest exercises" (or back, shoulders, arms, legs) | Opens the exercise library at that muscle. "Browse" opens all of it. |
| "Start the chest workout" (or "back day", "leg day") | Runs that muscle's five top picks, three sets each, and moves on by itself. |
| "Start my workout" | Runs the moves you starred, in order. |
| "Let's do incline dumbbell press" | Any move in the library works by its name or an everyday nickname ("bench press", "rdl"). |

Timed sets get a "halfway", "ten seconds" and a five-to-one countdown. Each set is saved on the phone the
moment it ends and pushed to GitHub right after (or later, if offline).

**The camera stays off until a set starts.** It turns on while Max counts down after "let's go baby", records the set,
and goes off again when the set is logged or stopped. The home screen shows no picture of you. Tap the camera button there
for a few seconds of preview to frame the shot, and tap it again while the preview is on to flip front and back. The
microphone still listens, because that is how Max hears "let's go baby".

## The exercise library

The app carries 277 exercises in 13 muscle groups: chest, shoulders, back, triceps, biceps, forearms, traps, abs and core,
quads, hamstrings, glutes, calves and cardio. Every one has a how-to that Max can read out loud: the set-up, the steps,
three cues and the common mistakes, plus a link to a demo video.

The home screen stays light. It shows the six-pack picks and a small **Browse all** button. You decide the rest:

- **Browse** opens the library: a search box, a tile for each muscle, and inside a muscle its top picks first, with
  filters for equipment (bodyweight, dumbbell, barbell, cable, machine, kettlebell, band).
- **Star a move** (the star in any list or how-to) to put it on your home screen. As soon as you have starred one,
  your moves replace the six-pack picks and the big button becomes **Start my workout**. You can star up to 12, and
  **Clear** in the library brings the six-pack picks back.
- **Start the chest workout**, a button inside each muscle or a voice command, runs that muscle's five top picks as a
  guided workout.

A move is saved under the library's name, so "bench press" and "Barbell Bench Press" are one exercise on the dashboard.

**Adding or changing an exercise.** The library is one file, `ios/MaxTrainer/MaxTrainer/exercises.json`, an array of
objects with `name`, `aliases` (what people say), `group`, `also` (other muscles), `equipment`, `mode` (`reps` or `timed`),
`amount` (default reps or seconds), `muscles`, `setup`, `steps`, `cues`, `mistakes` and `featured`. No code change is
needed. Keep the text plain, with letters, digits and basic punctuation only, because Max reads it aloud. A name or
nickname must not point at two different moves. The first moves listed for a group that are marked `featured` are its
top picks and its workout.

## Setup

1. Open `ios/MaxTrainer/MaxTrainer.xcodeproj` in Xcode (regenerate it with `xcodegen` from `ios/MaxTrainer`
   after adding files). Pick your team under Signing, plug in the iPhone, run.
2. In the app's Settings (gear icon):
   - **GitHub token**: a fine-grained personal access token for `viraone/maxtrainer-log` with
     *Contents: read and write*. Without it, sets stay on the phone until you add one.
   - **Claude API key** (optional): lets Max understand free-form speech, answer questions and give form
     feedback from a mid-set camera frame. Without it, the plain commands above still work offline.
3. Allow microphone, speech recognition and camera when asked.

Speech recognition runs on-device when the iPhone supports it. Max pauses listening while he talks, so wait
for him to finish before answering.

## Set videos and the AI trainer

Every recorded set is also uploaded as a small clip, and the dashboard can review your form from it.

**What happens on the phone.** "Let's go baby" starts recording. The clip is recorded upright for the way the phone really
stands, so a tripod laid on its side gives a landscape clip. When the set ends, the clip (540x960 or 960x540, about 1 Mbps,
roughly 3.5 MB per 30 seconds) is saved to Photos and uploaded to a **private** GitHub repository, `viraone/maxtrainer-media`, under
`videos/YYYY/MM/DD/`. The set's entry in `data/workouts.json` gets a `video` field with the clip's path. If the phone is
offline the clip waits on the phone and uploads later. Switch uploads off in Settings with "Upload each set's video to GitHub".

**One-time token step.** Your fine-grained GitHub token must include both repositories, `maxtrainer-log` and
`maxtrainer-media`, each with Contents: read and write. Edit an existing token in GitHub under Settings, Developer settings,
Fine-grained tokens. Use the same token in the app and on the dashboard.

**On the dashboard.** A set with a video shows "Watch & get AI feedback". The page downloads the clip with your token (it is
private, so nobody else can play it), plays it, and the **Analyze my form** button picks 8 still frames, sends them to
DeepSeek (`deepseek-flash`) and shows a score, what looked good, what to fix with a cue for each, and how form changed over
the set. The feedback is saved into that set's `ai` field in the log, so it is there next time. Paste your DeepSeek API key
into the dashboard once; it stays in that browser only. The review takes 20 to 30 seconds and costs a fraction of a cent.

**Watching and listening.** The player has its own controls: play, seek, 0.5x and 0.25x slow motion, and turn left or right
for a clip that was recorded sideways. The turn is saved on that set (`video.rotate`) and also applied to the frames the AI
sees, so it reviews an upright picture. After an analysis the trainer says the feedback out loud with your browser's own
voice (button "Hear your trainer", with a voice picker, speed, and a switch for talking right after each analysis). The
written feedback is tucked under "Show the written feedback". The voice comes from your computer: a Premium or Enhanced
voice (System Settings, Accessibility, Spoken Content) sounds far more natural than the default.

**Privacy notes.** Clips never touch the public repo. Pressing Analyze sends 8 stills of that clip to DeepSeek. Deleting a
set in Edit mode also deletes its clip from the private repo once you save.

**Data format additions** (`data/workouts.json`): `video: {path, bytes, repo, rotate}` (`rotate` is optional: 90, 180 or 270
degrees clockwise to turn the clip upright when it is shown) and
`ai: {score, headline, view, good[], fix[{area, issue, cue}], over_time, next_set, cannot_judge[], spoken, model, analyzed_at, frames}`
(`spoken` is what the trainer says out loud; older analyses have none, and the dashboard builds it from the other fields).

## Data format

`data/workouts.json` holds `{ "workouts": [ ... ] }`. Each entry has `exercise`, `timestamp` (ISO 8601, UTC),
`summary`, `cues`, `improvements`, and either `reps` or `duration_seconds`, plus `set_number`.
