---
name: fleet-comms-simulators
description: Use for any Fleet Comms iOS build, test, run or simulator work on a shared Mac. Triggers on simulator, ios-agent, xcodebuild test, simctl, pkill, parallel testing, slot, or "Waiting for a simulator slot".
---

# Fleet Comms simulators

The Mac's simulators are a shared, leased pool. Claim one slot, work on it, release it.

Simulator work here means the iPhone handset, `FleetCommsPhone.xcodeproj` with scheme `FleetCommsPhone`. The
macOS app in `NotchVoice.xcodeproj` builds and tests on the Mac with no simulator, as `CONTRIBUTING.md` says.

1. Claim a slot with a device type the pool has: `ios-agent up --device-type 'iPhone 18 Pro' --holder '<task name>'`. Run `ios-agent list` first, because only pooled types work: `ios-agent` refuses a type the pool lacks instead of waiting for it. Never run a bare `ios-agent up`: with no type it asks for iPhone 17 Pro, which no pool has.
2. Build, test and run on that lease: `ios-agent build`, `ios-agent test`, `ios-agent run`. Point any other tool at the slot's UDID (`eval "$(ios-agent env)"`).
3. The repo has two Xcode projects, so `ios-agent` cannot pick one by itself. A local, untracked `.ios-agent/project.json` naming `FleetCommsPhone.xcodeproj` and scheme `FleetCommsPhone` lets `ios-agent build`, `run` and `test` work; do not commit it.
4. "Waiting for a simulator slot" is a queue, not a fault. Report and wait, or pick another pooled type.
5. Never `pkill`, `killall` or `kill` ios-agent or any simulator or build process; a name match hits every task on the Mac. Stop your own builds and tests with `ios-agent stop --builds`.
6. Never `xcrun simctl create`, `clone` or `delete` a simulator, and never build onto one you made. A disposable simulator here means a leased pool slot.
7. Never run raw `xcodebuild test`. `ios-agent test` turns parallel testing off and holds the shared build locks. If raw `xcodebuild test` is unavoidable, target the leased slot's UDID and pass `-parallel-testing-enabled NO`. The macOS `NotchVoiceTests` testable already sets `parallelizable = "NO"`, and the phone scheme has no test target.
8. Release your lease when the work ends: `ios-agent release --yes`. Do not use `--erase` or `reset` on a slot that holds a certificate or a signed-in session.

Why: Xcode's default parallel testing clones the simulator several times per run. The clones are full simulators that the pool neither counts nor slims, and they can push host load high enough to break other tasks.
