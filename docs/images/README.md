# README screenshots

The six macOS screenshots were captured on macOS from isolated Debug builds on October 29, 2026, with temporary
bundle IDs `com.fleetcomms.proof.readme` (the original three images) and
`com.fleetcomms.proof.readmeplacements` (placements and question card). Bundle ID overrides are build
arguments and are not committed.
For these macOS screenshots, the installed app and its preferences were left unchanged.

- `listening.png`: the notch pill’s listening UI, with a neutral transcript and demo audio level.
- `spoken-reply.png`: the speaking-reply UI, with synthetic text and the speaker indicator.
- `settings.png`: the real Voice & Speech settings window, using isolated preferences and no accounts.
- `bottom-placement.png`: the listening card in the bottom-center placement.
- `side-placement.png`: the listening card and round buttons in the side-dock placement.
- `ask-user-question.png`: a neutral three-option Claude question, with the recommended choice selected.
- `phone-pairing.png`: the real Fleet Comms iPhone app on an iPhone simulator, unpaired with an empty link field. No pairing link or code is shown; the simulator has no camera, so the Scan QR Code control is unavailable. The top status-bar strip is cropped to remove its live clock.
- `phone-connected.png`: the real Fleet Comms app on an iPhone after pairing, showing Connected and the microphone control. The clock, signal and battery status bar is cropped out. The image is cropped to 1320 × 2640 and scaled to 600 × 1200 to match the pairing image; no app text or controls are retouched.

The existing `--capture-ui` / `--capture-reply-text` developer switches set the listening and reply demo
states. The question image uses `--question-proof` and `--question-proof-script` with the real
`scripts/ask-user-question.py` hook, a synthetic `AskUserQuestion` event, and a scratch firstmate home.
For the question image, no Claude provider session was started and the selected answer was not sent.
The macOS screenshots show the running app, not a live recognition, synthesis, provider, or fleet session.
No microphone input, real message, or login was used for those macOS captures.

For the macOS screenshots, window IDs came from `CGWindowListCopyWindowInfo`; `screencapture -x -o -l <windowID>` captured
only the isolated app’s windows. The pill captures were cropped and placed over a plain neutral backdrop
at 1120 × 320 pixels. The settings and question images are 1560 × 1184 pixels. These are close-ups of the
app surfaces; the desktop and Dock are omitted. PNGs are losslessly optimized; no text, controls, or app
content was retouched. Capture scripts, raw frames, and logs stay outside the repository. Temporary
DerivedData is removed after capture. The six macOS captures, one iPhone simulator pairing screen, and one Connected iPhone screen are the eight selected images checked in. Both iPhone images are 600 × 1200 and displayed at 300 pixels wide. The pairing image is cropped above the live clock; the Connected image removes the clock, signal and battery. No app text or controls are retouched.

For macOS capture reproduction, use a separate bundle ID, scratch `HOME` / `CFFIXED_USER_HOME`, `-modelsRoot`, event log,
and an empty `-firstmateHome` (a scratch home for the question hook). Disable the assistant and unsolicited
replies, leave onboarding incomplete
to avoid model downloads, and use only neutral demo text. Quit the isolated app and delete its temporary
preferences afterward. Never use the installed Mac app or its preferences for a macOS capture.
