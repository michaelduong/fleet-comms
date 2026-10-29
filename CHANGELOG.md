# Changelog

All notable changes to Fleet Comms. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and versions follow [semantic versioning](https://semver.org). Entries before 0.8.0 were reconstructed from the
merged pull requests; no releases were published for them.

## [Unreleased]

## [0.9.0] - 2026-10-29

### Added
- Settings › General › Placement: keep the pill in the notch, float it centred above the Dock, or dock a column
  of round buttons at the right screen edge with cards opening beside it. Floating placements open on the display
  under the pointer.
- `--capture-ui` also renders the pill in every placement and state.
- Claude question cards: an optional `AskUserQuestion` hook (`scripts/ask-user-question.py`) hands a
  session's questions to Fleet Comms, which shows them in the pill, on the same surface as listening and
  replies, with numbered options, the recommended choice, a typed or dictated reply and one page per
  question. Send returns the answers to the session; closing the question or a timeout falls back to the
  terminal picker.
- Settings › About: app version, source and license links, and a manual, anonymous GitHub release
  check with clear private/unpublished, network and rate-limit states.
- Optional Liquid Glass cards, English male Kokoro voices and voice previews in Settings.
- Read-only past-work lookup for the fleet messenger and both realtime voice lanes, confined to the
  selected firstmate home's data directory.
- Independent Grok Voice and ChatGPT Realtime voice choices for unsolicited session replies.
- Sparkle 2.10.1 updater integration and signed draft-release tooling. Automatic updates remain disabled
  pending a public repository, signing, notarization and update-feed validation.
- Open-source documentation: a user guide, security policy, contribution and issue templates, third-party
  notices and native README screenshots, including bottom-center, side-dock and Claude question cards.

### Changed
- App icon: Glass / voice, with a frosted-glass headset and five teal voice bars on smoked graphite.
  The transparent PNG master replaces the earlier SVG; `Design/render-icon.sh` regenerates all macOS sizes.
- Reply headers now use the Fleet Comms app logo; the menu-bar glyph matches the headset and voice icon.
- Waiting indicators use compact spring-animated pills. Bottom-center replies are narrower with the idle
  pill hidden, and reply cards open at the top while continuing to follow live transcripts.
- Fleet refresh timing is configurable, and messenger model choices are filtered by answer latency.

### Fixed
- Both Parakeet Realtime model variants now show NVIDIA Open Model License in Settings; Parakeet TDT v2
  and Fluid Speech Pro retain CC-BY-4.0 labels.
- Delayed replies and unsolicited session replies honor the selected realtime voice provider, report
  fallback failures, and preserve the intended spoken words in formatted replies and links.
- Read Whole Reply applies to both reply routes; unsolicited replies dismiss reliably, routine no-op
  replies stay quiet, and cancelled listening sessions no longer produce unwanted speech.
- Side-dock pending badges stay within panel bounds, and error cards dismiss cleanly.
- A spoken reply gets its reply window on every voice lane: with Keep Listening After Reply on, the pill
  listens for an answer after a Kokoro reply even when the voice lane is Grok or GPT, and dismisses on its own
  when nothing is said or when the models are not loaded. A silent reply now checks where the pointer really
  is before it leaves, so a card hidden under the pointer can no longer keep later replies on screen.
  A waiting Claude question never holds a reply; it returns once the reply has gone.

## [0.8.1] - 2026-10-28

### Added
- MIT license.

### Changed
- ChatGPT Realtime and Grok Voice are off on fresh installs, with separate opt-ins in Settings and notes
  that each uses your own subscription. Previously saved realtime selections are preserved.
- Clone instructions now use https://github.com/michaelduong/fleet-comms; internal app identifiers stay unchanged.

## [0.8.0] - 2026-10-28

Open-source preparation.

### Added
- A Settings window with General, Voice & Speech, Assistant, Realtime, Models and Advanced sections; the
  menu-bar menu keeps only the quick toggles (voice lane, fast assistant, read whole reply), Settings and Quit.
- First-run onboarding: microphone permission, firstmate home, starter model downloads.
- Settings › Models: every local model with its state, size, licence and source, with Download, Cancel and
  Delete; downloads are pinned to one Hugging Face revision each and resume where they stopped.
- Firstmate home discovery: homes under the standard install root (or `FM_HOME`) are offered; a single one is
  the default, otherwise onboarding asks. The home is no longer assumed.
- Clear states when an optional piece is missing: no Claude CLI, no FluidVoice, no Codex or Grok login, no home.
- An original app icon (SVG source in `Design/`, rendered into the asset catalog by `Design/render-icon.sh`).
- `Config/*.xcconfig` for signing, bundle id and version, with a gitignored `Local.xcconfig` for personal
  values; a fresh clone builds and runs with no Apple team.
- `scripts/release.sh` (archive, Developer ID export, notarize, staple, zip, dmg, tag, GitHub release) and
  `scripts/bump-version.sh`; this changelog; `CONTRIBUTING.md`; a README written for newcomers.
- Developer switches `--capture-ui` and `-modelsRoot`.

### Changed
- `Settings…` moved from a three-field window to the sectioned window above.

### Removed
- The `--debug-hooks` distributed-notification listener.
- Personal values from the tree: the owner's team id and home name, and a real inbox note id in a test.

## [0.7.0] - 2026-10-28
### Added
- Realtime calls hang up after a configurable quiet window: 5, 10 (default), 20 or 30 s after the model's last
  audio. Talking again resets it; model playback is never cut off by it.

## [0.6.0] - 2026-10-28
### Changed
- The visible product name is Fleet Comms: app bundle, menu, window titles, usage descriptions. The bundle id,
  defaults domain and the Application Support and Logs folder names stay `NotchVoice` so existing installs keep
  their settings, permissions and models.

## [0.5.0] - 2026-10-28
### Added
- Realtime voice lanes: ChatGPT Realtime (`gpt-realtime-2.1`) and Grok Voice (`grok-voice-latest`) as
  hands-free calls on the Codex and Grok CLI subscription logins, with barge-in, a `pass_to_first_mate` tool,
  first-mate replies read mid-call, per-lane voices, and spoken fallbacks to the on-device lane.

## [0.4.0] - 2026-10-28
### Added
- Speech speed (1.0x to 2.0x) using Kokoro's native speed control, applied at the next sentence.
- Keep Listening After Reply: the microphone opens for the dismissal window after a spoken reply so a follow-up
  needs no hotkey; at least 350 ms of VAD-confirmed speech starts a turn.

## [0.3.0] - 2026-10-28
### Added
- Smart Turn v3.2 as an optional end-of-turn decider (End of Turn › Smart Turn), running through ONNX Runtime,
  pinned to one revision and checked by SHA-256. Silence stays the default and the hard ceiling.

## [0.2.0] - 2026-10-28
### Added
- The fast assistant: one warm `claude --print` Haiku process answers quick questions out loud and hands real
  work to the first mate, with a read-only fleet summary from `fm-bearings-snapshot.sh`.
- Read Whole Reply, sentence-by-sentence synthesis so speech starts after the first sentence, and timing events.

## [0.1.0] - 2026-10-28
### Added
- Notch Voice v1: a pill in the notch, a global hotkey, Silero VAD and Parakeet recognition on device, Kokoro
  speech, notes to the first mate through `fm-inbox.sh` and spoken replies, a menu-bar menu and a WAV feed for
  testing without a microphone.
