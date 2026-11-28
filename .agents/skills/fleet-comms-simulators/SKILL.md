---
name: fleet-comms-simulators
description: Use for Fleet Comms handset builds, runs or simulator work on a shared Mac. Triggers on Fleet Comms simulator, ios-agent, xcodebuild test, simctl, pkill on ios-agent, or "Waiting for a simulator slot".
---

# Fleet Comms simulators

The Mac's simulators are a shared, leased pool. Claim one slot, work on it, release it.

Simulator work here means the iPhone handset, `FleetCommsPhone.xcodeproj` with scheme `FleetCommsPhone`. The
macOS app (`NotchVoice.xcodeproj`, scheme `NotchVoice`) builds and tests on the Mac with no simulator, as
`CONTRIBUTING.md` says.

1. Before the first build in a checkout, let `ios-agent` find the handset project (the repo has two Xcode projects) with an untracked `.ios-agent/project.json` containing `{"workspace": "FleetCommsPhone.xcodeproj", "scheme": "FleetCommsPhone"}`. Add it to `.git/info/exclude` and do not commit it.
2. Claim a slot with a device type the pool has: `ios-agent up --device-type 'iPhone 18 Pro' --holder '<task name>'`. Run `ios-agent list` first and name a type it lists, because this Mac's pool changes. Never run a bare `ios-agent up`: with no type it asks for iPhone 17 Pro, which no pool here has.
3. Build and run on that lease: `ios-agent build` and `ios-agent run`. Point any other tool at the slot's UDID (`eval "$(ios-agent env)"`). The handset scheme has no test target.
4. "Waiting for a simulator slot" is a queue, not a fault. Report and wait, or pick another pooled type.
5. Never `pkill`, `killall` or `kill` ios-agent or any simulator or build process; a name match hits every task on the Mac. Stop your own builds and tests with `ios-agent stop --builds`.
6. Never `xcrun simctl create`, `clone` or `delete` a simulator, and never build onto one you made. A disposable simulator here means a leased pool slot.
7. Never run raw `xcodebuild test` against a simulator; the macOS `NotchVoiceTests` suite runs with the command in `CONTRIBUTING.md`. If a raw simulator run is ever agreed as unavoidable, point it at the leased slot's UDID, pass `-parallel-testing-enabled NO`, and say which step `ios-agent test` could not run.
8. Release your lease when the work ends: `ios-agent release --yes`. Do not use `--erase` or `reset` on a slot that holds a certificate or a signed-in session.
