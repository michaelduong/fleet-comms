# README screenshots

Captured on macOS from this worktree’s own Debug build on October 29, 2026, with temporary
bundle IDs `com.fleetcomms.proof.readme` (the original three images) and
`com.fleetcomms.proof.readmeplacements` (placements and question card). Bundle ID overrides are build
arguments and are not committed.
The installed app and its preferences were left unchanged.

- `listening.png`: the notch pill’s listening UI, with a neutral transcript and demo audio level.
- `spoken-reply.png`: the speaking-reply UI, with synthetic text and the speaker indicator.
- `settings.png`: the real Voice & Speech settings window, using isolated preferences and no accounts.
- `bottom-placement.png`: the listening card in the bottom-center placement.
- `side-placement.png`: the listening card and round buttons in the side-dock placement.
- `ask-user-question.png`: a neutral three-option Claude question, with the recommended choice selected.

The existing `--capture-ui` / `--capture-reply-text` developer switches set the listening and reply demo
states. The question image uses `--question-proof` and `--question-proof-script` with the real
`scripts/ask-user-question.py` hook, a synthetic `AskUserQuestion` event, and a scratch firstmate home.
No Claude provider session was started and the selected answer was not sent.
These are screenshots of the running app, not a live recognition, synthesis, provider, or fleet session.
No microphone input, real message, or login was used.

Window IDs came from `CGWindowListCopyWindowInfo`; macOS `screencapture -x -o -l <windowID>` captured
only the isolated app’s windows. The pill captures were cropped and placed over a plain neutral backdrop
at 1120 × 320 pixels. The settings and question images are 1560 × 1184 pixels. These are close-ups of the
app surfaces; the desktop and Dock are omitted. PNGs are losslessly optimized; no text, controls, or app
content was retouched. Capture scripts, raw frames, and logs stay outside the repository. Temporary
DerivedData is removed after capture. Only the six selected images are checked in.

For reproduction, use a separate bundle ID, scratch `HOME` / `CFFIXED_USER_HOME`, `-modelsRoot`, event log,
and an empty `-firstmateHome` (a scratch home for the question hook). Disable the assistant and unsolicited
replies, leave onboarding incomplete
to avoid model downloads, and use only neutral demo text. Quit the isolated app and delete its temporary
preferences afterward. Never use the installed app or its defaults for capture.
