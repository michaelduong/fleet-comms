---
name: fleet-comms-simulators
description: Use for Fleet Comms handset (iOS) build, run or simulator work on a shared Mac. Triggers on ios-agent, simulator slot waits, simctl, or pkill for the Fleet Comms handset.
---

# Fleet Comms simulators

The Mac's simulators are a shared, leased pool. Claim one slot, work on it, release it.

Simulator work here means the iPhone handset, `FleetCommsPhone.xcodeproj` with scheme `FleetCommsPhone`. The
macOS app (`NotchVoice.xcodeproj`, scheme `NotchVoice`) builds and tests on the Mac with no simulator, as
`CONTRIBUTING.md` says.

1. Before the first build in a checkout, let `ios-agent` find the handset project (the repo has two Xcode projects) with an untracked `.ios-agent/project.json` containing `{"workspace": "FleetCommsPhone.xcodeproj", "scheme": "FleetCommsPhone"}`. Keep it untracked by adding it to the exclude file `git rev-parse --git-path info/exclude` prints, and do not commit it.
2. Claim a slot with a device type the pool has: `ios-agent up --device-type 'iPhone 18 Pro' --holder '<task name>'`. Run `ios-agent list` first and name a type it lists, because this Mac's pool changes. Never run a bare `ios-agent up`: it picks the type for you and can wait on one the pool lacks.
3. The claim boots, builds and launches. Later builds and runs on that lease use `ios-agent build` and `ios-agent run`; when another tool needs the destination, `eval "$(ios-agent env)"` only after it succeeds, never from a cached value. The handset scheme has no test target.
4. "Waiting for a simulator slot" is a queue, not a fault. Report and wait, or pick another pooled type.
5. Never `pkill`, `killall` or `kill` ios-agent or any simulator or build process; a name match hits every task on the Mac. Stop your own builds and tests with `ios-agent stop --builds`.
6. Never `xcrun simctl create`, `clone` or `delete` a simulator, and never build onto one you made. A disposable simulator here means a leased pool slot.
7. Never run raw `xcodebuild test` against a simulator; the macOS `NotchVoiceTests` suite runs with the command in `CONTRIBUTING.md`. If a raw simulator run is unavoidable and the task explicitly allows it, point it at the leased slot's UDID, pass `-parallel-testing-enabled NO`, and say which step `ios-agent test` could not run.
8. Release your lease when the work ends: `ios-agent release --yes`. Do not use `--erase` or `reset` on a slot that holds a certificate or a signed-in session.
