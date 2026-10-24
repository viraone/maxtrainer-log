# MaxTrainer

A voice-run personal trainer for iPhone, plus the workout dashboard it logs to.

- **`ios/MaxTrainer`** — the iOS app. Put the phone on a tripod, talk to Max.
- **`index.html` + `data/workouts.json`** — the dashboard, served by GitHub Pages at
  https://viraone.github.io/maxtrainer-log/. The app commits every set into `data/workouts.json`.

## Talking to Max

| You say | Max does |
| --- | --- |
| "Planks, thirty seconds" | Sets up a timed set. |
| "Three sets of ten push-ups" | Sets up rep-based sets. |
| "Let's go" | Counts down three, two, one and starts the set. |
| "Done" / "I did eight" | Ends a rep set, with the count if you give one. |
| "Three more sets" | Adds sets of the current exercise. |
| "Stop" | Cancels the running timer. |
| "Rest a minute" | Starts a rest timer. |
| "That's it for today" | Wraps up and pushes the log to the dashboard. |

Timed sets get a "halfway", "ten seconds" and a five-to-one countdown. Each set is saved on the phone the
moment it ends and pushed to GitHub right after (or later, if offline).

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

## Data format

`data/workouts.json` holds `{ "workouts": [ ... ] }`. Each entry has `exercise`, `timestamp` (ISO 8601, UTC),
`summary`, `cues`, `improvements`, and either `reps` or `duration_seconds`, plus `set_number`.
