# Answer Claude questions in Fleet Comms

Install: merge the `hooks` entry from [the settings snippet](../scripts/ask-user-question.settings.json) into the firstmate home's Claude settings, replacing both placeholder paths; keep the hook timeout above `FLEET_COMMS_ASK_TIMEOUT` (120 seconds by default, maximum 300).

The app must have that same home selected in General Settings. No settings are installed automatically.
The hook handles only `AskUserQuestion` from that home or its descendants. Other tools keep their normal behavior.

Fleet Comms shows the question in its pill, on the surface and at the width it already uses for listening
and replies, in every placement: the session label, option descriptions, recommended badges, one to four
question pages, multi-select choices, and a custom reply field. Long questions show three lines with a
Show more toggle; option descriptions are one line until the option is chosen. A waiting question fills the
pill only while it is idle; a reply, a voice note or a call takes the pill first and the question returns
afterwards. Select answers on each page, then press Send. Clicking the reply field lets the pill take the
keyboard without activating the app, and it gives the keyboard back as soon as the question is gone. The
mic uses the existing local dictation models and microphone permission; the live transcript shows in the
reply row and lands in the reply field for review before sending. It does not send a note or start a
realtime call. `FLEET_COMMS_AGENT_LABEL` optionally sets the agent label; otherwise it uses the Claude
session ID prefix.

The bridge follows the current [Claude hook contract](https://code.claude.com/docs/en/hooks#pretooluse-decision-control):
return `permissionDecision: "allow"` and `updatedInput` with the original input plus an `answers` map keyed
by exact question text. Selected labels retain their original `(Recommended)` suffix; multi-select labels
and any custom text are joined with commas, as required by Claude.

The app publishes a heartbeat and reads private request directories in
`<firstmate-home>/state/fleet-comms-questions/`. Requests have unique IDs and deadlines. The hook waits at
most 120 seconds, exits silently without a decision on timeout, app loss, malformed input, or dismissal,
and removes its request. Closing the card immediately returns control to the terminal picker. A missing
app skips the bridge immediately. A frozen app is detected within three seconds. Expired/removed requests
disappear from the card and late answers cannot attach to a different tool call. The Sent confirmation
appears only after the waiting hook consumes the answer.

Claude runs this hook **before** opening its terminal picker. The terminal picker appears after fallback,
when the card has been withdrawn, so there are never two active answer surfaces. Cancelling the hook also
withdraws its card; a forced kill is bounded by the request deadline. No post-tool hook is required.
Question speech is optional and is not enabled by this integration.

Run the hook protocol checks with `python3 scripts/test-ask-user-question.py`; native store/draft tests are
`NotchVoiceTests/AskQuestionTests`. For a real-session proof, use the settings snippet with
`claude --setting-sources '' --settings <scratch-settings.json>` from a scratch home. Ask Claude to call
`AskUserQuestion`, answer from the app, and confirm its final reply contains the chosen answers. Repeat
with `FLEET_COMMS_ASK_TIMEOUT=5` in the hook command and let the picker appear unanswered.

Debug builds with a `com.fleetcomms.proof.*` bundle ID accept `--question-proof <capture-folder>`.
This starts only the real pill and question bridge, skips model loading and other fleet connections, and
captures the rendered pill, cropped to the question, whenever it changes. `--question-proof-script <file>`
runs store actions from a file (see CONTRIBUTING.md) so captures need no pointer. Pair it with a private
`CFFIXED_USER_HOME`, scratch `-firstmateHome` and `-modelsRoot`, and a task-scoped `NOTCH_VOICE_EVENT_LOG`.
The installed app and owner defaults must remain untouched. Captures use the view layer; translucent
materials appear flat.
