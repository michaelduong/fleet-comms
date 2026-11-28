# Repository Guidelines

Fleet Comms is a voice front end for Firstmate: a macOS notch app in `NotchVoice.xcodeproj` (scheme
`NotchVoice`, module `NotchVoice`, product `Fleet Comms.app`) and an iPhone handset in
`FleetCommsPhone.xcodeproj` (scheme `FleetCommsPhone`). Build, test, style, signing and release steps are in
[`CONTRIBUTING.md`](CONTRIBUTING.md); usage, configuration and architecture are in [`README.md`](README.md)
and [`docs/guide.md`](docs/guide.md). `project.yml` and `Phone.yml` are the sources for the Xcode projects.

Simulator work (the iPhone handset): claim a pooled slot with
`ios-agent up --device-type 'iPhone 18 Pro' --holder '<task>'` (never a bare `ios-agent up`; `ios-agent list`
shows the pooled types), then use
`ios-agent build`, `ios-agent test` and `ios-agent run` on that slot, point any other tool at its UDID, and
release it with `ios-agent release --yes`. Never `simctl create`, plain `xcodebuild test`, or `pkill` on
ios-agent or simulators; the one exception and the queue behaviour are in
[`.agents/skills/fleet-comms-simulators/SKILL.md`](.agents/skills/fleet-comms-simulators/SKILL.md).
