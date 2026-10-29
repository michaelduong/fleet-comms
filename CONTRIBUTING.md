# Contributing

Thanks for looking at Fleet Comms. This page covers building, style, tests, the developer switches and how a
release is cut. For usage and configuration, see the [user guide](docs/guide.md).
Report vulnerabilities through [SECURITY.md](SECURITY.md), without posting details publicly.

## Setup

```sh
git clone https://github.com/michaelduong/fleet-comms.git
cd fleet-comms
brew install xcodegen swiftlint swiftformat
xcodegen generate
cp Config/Local.xcconfig.example Config/Local.xcconfig   # optional: your team and bundle id
xcodebuild -project NotchVoice.xcodeproj -scheme NotchVoice -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build build
```

`project.yml` is the source of truth for the Xcode project; run `xcodegen generate` after changing it and
commit the regenerated `NotchVoice.xcodeproj`. The repository is `fleet-comms`; the Xcode project, target
and Swift module remain `NotchVoice`, and the product is `Fleet Comms.app`.

## Style

- Swift 6 with strict concurrency. Small files and types; one responsibility each.
- Run SwiftLint 0.65.1 and SwiftFormat 0.64.4 on the files you touch (`swiftlint lint --strict <files>`,
  `swiftformat <files>`); the configuration is in the repo root.
- Every new Swift file starts with the house header, including `Created by Michael Duong on <M/d/yy>.`
- Every UI control gets an accessibility identifier.
- Comment a non-obvious reason, constraint or workaround, not what the code already says.
- No personal data in the tree: no home paths, account names, team ids, note ids or transcript text in
  code, tests, fixtures or docs. Launch arguments and `Config/Local.xcconfig` are for local values.

## Tests

```sh
xcodebuild -project NotchVoice.xcodeproj -scheme NotchVoice -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build test
```

Run `Tests/ReleaseScriptTests.sh` for credential-refusal checks and keychain-profile/named-API-key dry-run
preflight fixtures (mocked commands; no signing, submissions or key generation).

The ordinary suite is fast and needs no models or network. Two opt-in suites exercise real hardware and the
network; each is enabled by an environment variable passed through `xcodebuild` with the `TEST_RUNNER_` prefix:

- **Audio proofs** (`NOTCH_VOICE_AUDIO_PROOF_ROOT`): play a fixed reply at several speeds and feed generated
  speech and silence through the real VAD and recognizer, with a temporary fake inbox. Results land in
  `audio-proof.txt` under that root. Needs the models already downloaded.
- **Download proof** (`NOTCH_VOICE_MODEL_PROOF_ROOT`): downloads the starter set and Smart Turn into that root
  through the Models library, deletes and re-downloads Smart Turn, and writes `download-proof.txt` with timings.

```sh
root="$(mktemp -d)"
TEST_RUNNER_NOTCH_VOICE_MODEL_PROOF_ROOT="$root" xcodebuild -project NotchVoice.xcodeproj -scheme NotchVoice \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build \
  -only-testing:NotchVoiceTests/ModelDownloadProofTests test
cat "$root/download-proof.txt"
```

The opt-in `TranscriptProofTests` suite uses `TEST_RUNNER_FLEET_COMMS_TRANSCRIPT_PROOF_ROOT=<folder>` to
render long replies in light and dark, check that replies open at the top while speaking and stay there
when the next reply arrives, check two consecutive realtime outreach replies for both providers, and
verify that live transcription still follows new text after outreach. It needs no network, microphone
or speech models. `SpeechScrollProofTests` in the same opt-in checks playback-paced following, a fresh
start for the next reading, and a native wheel gesture pausing auto-follow. `SpeechPlaybackTests`
checks alignment across Markdown, unspoken introductions, summary suffixes and Unicode without UI.

`SpeechScrollAudioProofTests` uses `TEST_RUNNER_FLEET_COMMS_SPOKEN_AUDIO_PROOF_ROOT=<folder>` and a scratch
`-modelsRoot` to play a long synthetic Kokoro reply and buffered outreach audio through both provider
paths. It saves start/middle/end frames and scroll offsets. The buffered proof uses generated PCM,
with no provider connection, microphone input or inbox activity. Use an isolated proof bundle ID,
private `CFFIXED_USER_HOME`, and scratch model copies; the installed app and its defaults stay untouched.

`MessengerLookupProofTests` exercises the real subscription CLI from the built app's assistant. Set
`TEST_RUNNER_FLEET_COMMS_LOOKUP_PROOF_ROOT=<scratch-folder>` and
`TEST_RUNNER_FLEET_COMMS_LOOKUP_PROOF_QUESTION=<lookup-question>`; optionally set
`TEST_RUNNER_FLEET_COMMS_LOOKUP_PROOF_DATA=<firstmate-data-folder>` and
`TEST_RUNNER_FLEET_COMMS_LOOKUP_PROOF_EXPECTED_FOLDER=<expected-path-fragment>` to assert a direct answer.
Without the data folder it measures the no-lookup baseline. `TEST_RUNNER_FLEET_COMMS_LOOKUP_PROOF_MODEL`
selects a candidate model (default `haiku`). It saves lookup and normal-handoff answers and timings only
under the supplied proof root; no inbox note is sent. Always use an isolated `FLEET_COMMS_BUNDLE_ID`.

`RealtimeLookupProofTests` makes a real call from an isolated Debug test host, feeds a question WAV,
and requires the expected absolute folder in the model's spoken transcript without an inbox handoff.
Set `TEST_RUNNER_FLEET_COMMS_REALTIME_PROOF_ROOT`, `TEST_RUNNER_FLEET_COMMS_REALTIME_PROOF_WAV`,
`TEST_RUNNER_FLEET_COMMS_REALTIME_PROOF_DATA`, `TEST_RUNNER_FLEET_COMMS_REALTIME_PROOF_EXPECTED_FOLDER`,
and `TEST_RUNNER_FLEET_COMMS_REALTIME_PROOF_LANE` (`chatgpt` or `grok`). Use a
`com.fleetcomms.proof.*` bundle ID and set `TEST_RUNNER_NOTCH_VOICE_EVENT_LOG` to a task-scoped file;
the `realtime_lookup` event records tool latency without text. Existing subscription logins are used.
Keep the proof's transcripts and tool-argument JSON private; do not include them in a PR.
Set `TEST_RUNNER_FLEET_COMMS_REALTIME_PROOF_OUTREACH=1` to verify lookup after an initial outreach reading.

`RealtimeLookupProofTests.liveOutreachReadsSuppliedText` checks a provider's initial outreach reading with
synthetic text. Set `TEST_RUNNER_FLEET_COMMS_OUTREACH_PROOF_ROOT`,
`TEST_RUNNER_FLEET_COMMS_OUTREACH_PROOF_WAV` (silence), `TEST_RUNNER_FLEET_COMMS_OUTREACH_PROOF_TEXT`,
and `TEST_RUNNER_FLEET_COMMS_OUTREACH_PROOF_LANE` (`grok` or `chatgpt`). Use an isolated proof bundle ID
and task-scoped event log. It saves the supplied text and provider transcript privately under that root.

`RealtimeReplyProofTests` drives the app's actual delayed voice-note and outreach delivery routes with
GPT Realtime / Echo and no local voice models. Set `TEST_RUNNER_FLEET_COMMS_REPLY_ROUTING_PROOF_ROOT`
and `TEST_RUNNER_FLEET_COMMS_OUTREACH_PROOF_WAV` (silence), with an isolated proof bundle ID. It checks
completed provider playback, saves only synthetic proof transcripts, and renders visible failure reasons
at the largest text size in light and dark. It sends no inbox note.

The audio proof suite also checks unsolicited Kokoro replies: silence closes the hovered reply window
after five seconds, while accepted speech keeps the existing reply flow.

## Claude question cards

Install: merge the `hooks` entry from [`scripts/ask-user-question.settings.json`](scripts/ask-user-question.settings.json)
into the firstmate home's Claude settings with both placeholder paths filled in. Nothing installs itself; see
[docs/ask-user-question.md](docs/ask-user-question.md) for the protocol, the hook tests
(`python3 scripts/test-ask-user-question.py`), and the scratch-session proof.
`AskQuestionDictationProofTests` in the audio proof suite feeds a spoken reply through the real recognizer
into a question draft and checks that no note is sent.

## Developer switches

All are launch arguments or environment variables of the app; none ship enabled.

| Switch | Effect |
| --- | --- |
| `--outreach-projects-root <folder>` | Debug builds with a `com.fleetcomms.proof.*` bundle ID only: read unsolicited session replies from an isolated transcript root. Pair with a scratch `-firstmateHome`, `-modelsRoot`, and `-outreachVoice kokoro\|grokVoice\|gptRealtime`; `--outreach-reply-wav <file>` feeds the follow-up turn instead of the microphone for an isolated proof. |
| `--feed-wav <path>` | Plays a recording through the real listening pipeline once the models are ready, at real-time pace and followed by silence. Notes sent this way start with `TEST notch-voice:`. Also available as Settings › Advanced › Feed WAV File as Speech…. |
| `--appearance light\|dark` | Forces the app's appearance without touching the system setting. |
| `--capture-reply-text <file>` | With `--capture-ui`, renders the file as a long reply in every placement, while speaking and after speech. |
| `--capture-card-themes <folder>` | Captures real compositor screenshots of reply cards in every theme and placement over light and dark backdrops, plus General Settings, then quits. Requires Screen Recording permission. Skips hotkeys, models and fleet connections; use a separate bundle ID and scratch home for proof. |
| `--capture-about <folder>` | Debug proof only, with a `com.fleetcomms.proof.*` bundle ID: captures About and Sparkle’s standard prerelease setup error in light and dark without starting any update checks; skips models, hotkeys and fleet connections. |
| `--question-proof <folder>` | Debug proof only, with a `com.fleetcomms.proof.*` bundle ID and a scratch `-firstmateHome`: runs only the pill and the Claude question bridge, and writes a PNG of the pill (plus its screen rectangle) into the folder each time the question changes; skips models, hotkeys and fleet connections. `--question-proof-script <file>` drives the question from a file, one action per line (`wait`, `select N`, `go N`, `type TEXT`, `send`, `consume`, `dismiss`, `dictate TEXT`, `placement NAME`, `quit`), so captures need no pointer. |
| `--capture-ui <folder>` | Opens Settings and onboarding, renders every section and step to PNG files in the folder, then quits. Used for PR screenshots. |
| `--capture-thinking yes` | With `--capture-ui`, captures thinking, waiting and reply states over a neutral proof backdrop; writes its screen rectangle for recording. Use `--capture-thinking-placement notch\|bottomCenter\|sideDock` to hold one placement. |
| `--pending-replies <count>` | With `--capture-ui`, renders the pill placements with that pending-reply count (including wide badges). |
| `-modelsRoot <folder>` | Keeps every model under another folder instead of `~/Library/Application Support/NotchVoice/Models`. |
| `-onboardingCompleted NO` | Shows the first-run window again (also Settings › Advanced › Show Onboarding Again). |
| `-<setting> <value>` | Any setting for one launch the usual `UserDefaults` way, e.g. `-textSize largest`, `-assistantEnabled NO`, `-voiceLane grokVoice`, `-firstmateHome /path/to/home`. |
| `NOTCH_VOICE_EVENT_LOG=<file>` | Debug builds only: writes the event log to that file. |

To test against a fresh settings domain without touching an installed copy, build with a different
`FLEET_COMMS_BUNDLE_ID` in `Config/Local.xcconfig` and point `-modelsRoot` at a scratch folder:

```sh
"build/Build/Products/Debug/Fleet Comms.app/Contents/MacOS/Fleet Comms" \
  -onboardingCompleted NO -modelsRoot /tmp/fleet-comms-models --appearance dark --capture-ui /tmp/shots
```

## App icon

`Design/AppIcon.png` is the approved 1024 × 1024 transparent **Glass / voice** master: a frosted-glass headset
on smoked graphite with five teal voice bars. Run `Design/render-icon.sh` to regenerate every macOS size in
the asset catalog and `Design/AppIcon-preview.png`, which the README displays. Each size is downscaled directly
from the master with macOS `sips`; the 1024 px catalog entry is an unchanged copy. The previous SVG is retired
and remains in Git history.

## Pull requests

- One topic per PR, with separate commits per area where it helps review.
- The description has three sections: **Testing** (what ran and the result), **Risk** (what could break and
  how badly) and **How to revert**.
- Prove UI changes by running the app; attach screenshots of each changed window in light and dark.

## Third-party licenses

Keep [third-party notices](docs/THIRD_PARTY_NOTICES.md) current when dependencies or model revisions change.
Preserve upstream copyright and license texts, and include the applicable notices with binary distributions.
Model weights have separate terms and are not covered by the app’s MIT license.

## Releases

Versions are semantic and come from one place, `Config/Version.xcconfig` (`MARKETING_VERSION` for the version,
`CURRENT_PROJECT_VERSION` for the build number). `CHANGELOG.md` has one section per version.

Sparkle 2.10.1 is pinned exactly in `project.yml` and `Package.resolved`. About's **Check for Updates**
uses `SPUStandardUpdaterController`. When enabled, Sparkle owns the scheduler and its standard permission
prompt on the second launch; automatic checks are opt-in. We deliberately do not set
`SUEnableAutomaticChecks` or force a preference at runtime. Anonymous system profiling is disabled.

Updates remain disabled until public distribution and signing are configured.
`Config/Sparkle.xcconfig` currently has `FLEET_COMMS_UPDATES_ENABLED = NO` and a clearly marked
`SUPublicEDKey` placeholder. Both explicit activation and a valid 32-byte public key are required.
Until then the controller is created without starting; the button uses Sparkle's standard error UI to
explain the hold. No feed request, background check, download or install is started. The old anonymous
GitHub version-comparison path has been removed.

### One-time setup by the project owner

1. Make the repository public and arrange a Developer ID Application certificate and notarization credentials.
2. Resolve the pinned Swift Package. Its tools are under
   `<DerivedData>/SourcePackages/artifacts/sparkle/Sparkle/bin/`. Use those tools from Sparkle **2.10.1**.
3. On the signing Mac, run `"$FLEET_COMMS_SPARKLE_BIN/generate_keys" --account fleet-comms` once.
   Sparkle stores the private EdDSA key in the login Keychain, under service
   `https://sparkle-project.org`, account `fleet-comms`. It displays the **public** verification key.
   Put only that public value in `FLEET_COMMS_SPARKLE_PUBLIC_KEY` in `Config/Sparkle.xcconfig`.
   Never commit, log, paste into an issue, or pass the private key in arguments/environment variables.
   Keep a secure recovery backup of the signing Mac/Keychain; do not generate a new key per release.
4. Change `FLEET_COMMS_UPDATES_ENABLED` to `YES` only in the reviewed go-public change. Commit it with
   the public verification key and preserve that key for subsequent releases. Keep the Sparkle tools'
   Keychain access local to the signing Mac. The script's `generate_keys -p` invocation is lookup-only;
   it compares the existing public key without printing it or creating a key.
5. Store a notarization profile with `xcrun notarytool store-credentials fleet-comms` interactively,
   or select an existing `asc` authentication profile with `FLEET_COMMS_NOTARY_KEY_NAME`.
   The script resolves that profile's key ID and issuer without exporting a key and passes its existing
   `AuthKey_<key-id>.p8` file to `notarytool --key/--key-id/--issuer`. Files are looked up under
   `~/.appstoreconnect/private_keys`, or `FLEET_COMMS_NOTARY_KEY_DIR`. Choose either the named key
   or `FLEET_COMMS_NOTARY_PROFILE`, never both. Never put passwords or private API key files in this tree.

### Preparing a release

1. Run `scripts/bump-version.sh <version>`, fill in `CHANGELOG.md`, and commit. Increment the numeric build
   on **every** release; Sparkle compares `CFBundleVersion`. Work from the clean, reviewed `main` commit
   that matches GitHub. Existing tags/releases, including the private draft, must not be overwritten.
2. Export `FLEET_COMMS_IDENTITY` (the exact Developer ID Application identity name), `FLEET_COMMS_TEAM`,
   and `FLEET_COMMS_SPARKLE_BIN` (the pinned distribution's `bin` directory).
   Optional names: `FLEET_COMMS_NOTARY_PROFILE` and `FLEET_COMMS_SPARKLE_ACCOUNT` (both default to
   `fleet-comms`), and `FLEET_COMMS_DIST` for output (default `dist/`). These are identifiers/paths, never
   private key values. `gh-axi`, `xcsift`, Python 3, Xcode and the signing/notary credentials are required.
3. `scripts/release.sh --dry-run` performs **read-only preflight**. It stops at the first missing
   credential; it never falls back to local signing or builds/packages an unsigned release.
4. `scripts/release.sh --prepare-draft` archives and exports with Developer ID, notarizes the app via a
   temporary zip, staples and validates the app, then creates the final zip and a DMG from that stapled
   app. It signs, notarizes and staples the DMG. It runs `generate_appcast` with the Keychain account,
   checks the EdDSA signature and enclosure metadata, and uploads zip, DMG, appcast and SHA-256 sums to
   a **draft** GitHub release. It never publishes, marks a release latest, or pushes a tag itself.
   Xcode archive/export handles embedded framework signing; deep signature verification and Gatekeeper
   assessment must pass before upload. Existing output directories/releases are refused.

### Feed hosting and public release gate

The feed is a GitHub Releases asset at
`https://github.com/michaelduong/fleet-comms/releases/latest/download/appcast.xml`.
Each new stable release carries `appcast.xml`, with its enclosure pointing to that release's versioned
zip URL. This keeps feed promotion and binary promotion in the same GitHub release, without a second
GitHub Pages deployment, branch or domain. A private repository or draft asset is inaccessible to
anonymous clients; it cannot be used for public Sparkle checks. The feed contains one full signed
update; deltas and historical entries are intentionally not generated yet.

Before manually publishing the draft as **latest stable**, the project owner must inspect the artifacts,
validate Developer ID/notarization and EdDSA trust on the signing Mac, and test a signed older build
upgrading to the signed candidate using an isolated test feed. After publication, verify anonymous
access to the latest appcast and versioned enclosure, the second-launch permission prompt, manual
check, opt-in background check and actual installation/relaunch on a clean Mac. Do not claim these
release-only checks passed from an ad-hoc proof. Publishing or promoting a release without its appcast
would break that stable feed URL. Never mutate an already-published zip after signing its appcast.

Current branch validation can cover the local build, ordinary tests, configuration/refusal tests, and
About/error screenshots under a separate `com.fleetcomms.proof.*` bundle ID. Developer ID proof signing can be checked locally when authorized;
notarization, appcast signing and live installation await the go-public setup. No EdDSA key is generated
as part of implementation or proof. Personal-only app waiver: largest/accessibility text-size checks
are skipped; the changed UI is inspected in light and dark.
