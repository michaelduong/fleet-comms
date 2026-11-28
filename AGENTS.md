# Repository Guidelines

Fleet Comms is a voice front end for Firstmate: a macOS notch app in `NotchVoice.xcodeproj` (scheme
`NotchVoice`, module `NotchVoice`, product `Fleet Comms.app`) and an iPhone handset in
`FleetCommsPhone.xcodeproj` (scheme `FleetCommsPhone`). Build, test, style, signing and release steps are in
[`CONTRIBUTING.md`](CONTRIBUTING.md); usage, configuration and architecture are in [`README.md`](README.md)
and [`docs/guide.md`](docs/guide.md). `project.yml` and `Phone.yml` are the sources for the Xcode projects.

Simulator work (the iPhone handset): point `ios-agent` at `FleetCommsPhone.xcodeproj` in an untracked
`.ios-agent/project.json`, claim a pooled slot with `ios-agent up --device-type '<pooled type>'
--holder '<task>'` (never a bare `ios-agent up`; `ios-agent list` shows the types, such as `iPhone 18 Pro`),
then keep builds and runs on that slot with `ios-agent build` and `ios-agent run`, use its UDID from
`ios-agent env` for any other tool, and release it with `ios-agent release --yes`. Never `simctl create`, raw
`xcodebuild test` against a simulator, or `pkill` on ios-agent or simulators. The macOS tests stay as
`CONTRIBUTING.md` describes; the queue behaviour and the raw-test exception are in
[`.agents/skills/fleet-comms-simulators/SKILL.md`](.agents/skills/fleet-comms-simulators/SKILL.md).
