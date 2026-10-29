# Fleet Comms guide

[Back to the README](../README.md) · [Developer guide](../CONTRIBUTING.md)

## First run

The first launch opens a short setup window:

1. **Microphone**: allow it (the mic is on only while the pill is listening). No Accessibility access is needed;
   the hotkey is a system hot key.
2. **Firstmate**: pick a firstmate home. Homes found under `~/.local/share/production-agent-stack/firstmate/`
   (or in `FM_HOME`) are offered; a single one is chosen for you. Any folder with `bin/fm-inbox.sh` works.
3. **Models**: download the three starter models (about 310 MB): Silero VAD, the Kokoro voice and the Parakeet
   Realtime recognizer. Skipped downloads happen on first use instead.

Every step can be skipped and revisited in Settings (menu-bar icon › **Settings…**, or ⌘,).

## Features

| Action | How |
| --- | --- |
| Talk | Hotkey (default ⌥ Space) or click the pill; with follow-up listening on, speak during the listening window after a reply. |
| Send | Automatic after the silence threshold (default 0.8 s), when the model detects end of utterance, or, with End of Turn › Smart Turn, when Smart Turn hears a finished turn. |
| Cancel without sending | Esc, or the hotkey again, while listening. |
| Interrupt the reply | Press the hotkey while it is speaking: speech stops and listening starts. |
| Dismiss the reply | The ✕ button, the hotkey to talk again, or wait: it folds away 5 s after it is spoken. Resting the pointer on the pill holds it open. |

If no reply arrives within the reply timeout (default 60 s), the pill says "Still working" and folds back into
the notch with an orange dot; the reply is still spoken when it lands.

### Menu and Settings

The menu-bar icon keeps the quick toggles: **Voice Lane**, **Fast Assistant**, **Read Whole Reply**,
**Settings…** and **Quit**. When macOS hides the icon because the menu bar is full beside the notch, the menu
opens where you clicked in the menu bar, or under the notch.

Settings has seven sections:

- **General**: the firstmate home (with the homes found on this Mac), hotkey, placement, text size, dismiss
  delay, the "still working" timeout and Launch at Login.
- **Voice & Speech**: speech model, end of turn (Silence or Smart Turn), silence threshold, the Kokoro voice,
  speech speed (1.0x to 2.0x, pitch preserved), Read the whole reply, Keep listening after a reply.
- **Assistant**: the messenger on or off, its model and Claude CLI path, active/idle fleet refresh rates,
  and Refresh now. Only models meeting the measured five-second median limit are offered; currently Claude Haiku.
- **Realtime**: the voice lane, each lane's sign-in state and voice, unprompted outreach voice, the hang-up window, and the privacy note.
- **Models**: every local model with its state, size, source and Download or Delete buttons; disk use.
- **Advanced**: the inbox script override, the event log, the WAV feed developer tool and "Show Onboarding Again".
- **About**: version, license, and a manual anonymous check for published releases.

### Placement

Settings › General › Placement chooses where the pill lives; the change applies at once.

| Placement | At rest | Open |
| --- | --- | --- |
| **Notch** (default) | The camera housing with a small ear each side; a strip at the top centre on a Mac without a notch | A card hanging from the notch |
| **Bottom center** | Hidden; invoke with the hotkey or menu | A card growing upwards above the Dock; hides again on dismissal |
| **Side dock** | A column at the right edge: a round Talk button (with the pending-reply count) and a “…” button that opens the menu-bar menu | A card beside the column, pointing at Talk |

Everything else is the same in each placement: the hotkey, listening, replies and their spoken text, auto-dismiss,
transcript scrolling and Settings. The notch stays on the display that has it. The two floating placements open
on the display under the pointer each time the pill opens, so the card appears where you are working, and move
with the Dock and menu bar when displays change.

### Fast assistant

One warm `claude --print` process (Claude Haiku, stream-json in and out, no tools, MCP servers, settings, hooks or
saved sessions) answers each utterance with structured output: what to say, and whether to hand off. It
answers greetings, chit-chat, demo requests and questions about the fleet; anything that asks for work (build,
fix, merge, dispatch, approve, …) or that it cannot answer is filed as an inbox note, and it says "Passed to the
Firstmate. I'll tell you when it answers." You can keep talking to it while that is pending; Firstmate's
reply is announced ("Firstmate replied.") and read when it lands.

- Fleet context: `bin/fm-bearings-snapshot.sh --json` from the firstmate home, refreshed in the background every
  60 s while you are talking and every 4 minutes after 10 quiet minutes by default, trimmed to a short summary
  without links or paths. Settings › Assistant offers independent active and idle intervals of 30 s, 1, 2, 4 or
  5 minutes, or Off — manual; Refresh now works in manual mode. A turn never waits for a snapshot. Missing
  context is handed off; context expires after the greater of 5 minutes or twice the active interval
  (5 minutes in manual mode). Changes apply immediately without restarting the messenger.
- Memory: the process keeps the conversation. After 24 turns, or 15 minutes of quiet, a fresh process starts;
  the last few exchanges are repeated to it after 24 turns.
- Past work: lookup questions search Markdown and text records under the selected firstmate home's `data/`
  folder, including reports, briefs and the backlog. The messenger answers from matching excerpts and names
  the file or folder; image files are listed by path, without inspecting their contents. Search is bounded,
  so missing or ambiguous evidence is handed off. Old reports never substitute for live fleet status.
  The shared app-side reader rejects symlinks, hard links, hidden files, sensitive names, `config/` and
  `state/`; the model CLIs retain no tools or shell access. This also covers the candidate GPT/Grok messengers.
  Realtime voice lanes expose the same scoped reader through their past-work lookup tool. Conversation archives are not searched.
- Failures are spoken: if the CLI is missing, the process dies or a turn takes over 20 s, your words go straight
  to Firstmate and the pill says so. A process that dies is restarted. Talking over "Thinking…" drops that
  turn.
- With the assistant off, every utterance goes straight to Firstmate.

### Voice lanes

**Voice Lane** picks who answers out loud. **On-device** (the default) is everything above. The two realtime
lanes are speech-to-speech models reached on your own subscription logins, with no API key:

| Lane | Model | Login it reuses (read-only) | Default voice |
| --- | --- | --- | --- |
| ChatGPT Realtime | `gpt-realtime-2.1` | the Codex CLI's ChatGPT login, `~/.codex/auth.json` (`codex login`) | Cedar |
| Grok Voice | `grok-voice-latest` | the Grok CLI's SuperGrok login, `~/.grok/auth.json` (`grok login`) | Rex |

Settings › Realtime › **Unprompted outreach** independently chooses Kokoro (the default), Grok Voice, or
GPT Realtime for messages Firstmate sends on its own. Replies to voice notes keep their current voice.
Realtime outreach uses the selected lane's existing login and voice option. It reads the supplied message,
then keeps the same session open as a normal two-way call with a live microphone, visible call controls,
fleet context and the usual handoff tools. Reading does not require microphone permission; if permission is
missing, the reading finishes and an explanation appears before follow-up listening. Hang up with the
normal controls, or let the outreach quiet window expire (default 25 seconds, configurable independently).
Before playing the outreach, the app checks the transcript for the exact words in order (ignoring punctuation
and capitalization). A failed, changed, empty, or slow reading shows why and falls back to one-way Kokoro
when it is loaded; otherwise the reply stays visible with the explanation. Generation has a
12-second limit and audio is capped at two minutes; longer messages use Kokoro. Kokoro retains Read Whole Reply
behavior; realtime outreach and its fallback read the complete supplied message.

Both lanes are **off by default**. Enable each lane in Settings › Realtime, then choose it as your voice lane.
ChatGPT uses your own ChatGPT subscription; Grok Voice uses your own SuperGrok subscription.

These lanes are **opt-in and unofficial**: neither OpenAI nor xAI documents using the Codex or Grok CLI login
this way, and either vendor may change or block it. A lane without a login on this Mac cannot be chosen; the
Realtime settings say which command signs in.

On a realtime lane the hotkey opens a hands-free call instead of one utterance: talk, pause, and the model answers;
talk over it and its audio stops at once. The hotkey or Esc hangs up, and so does the configured quiet window
(5, 10, 20 or 30 s, default 10) after the model's last audio finishes.

- The model chats and answers fleet questions from the same read-only fleet summary as the fast assistant.
  Work requests go to Firstmate through the same inbox note, via a `pass_to_first_mate` tool call. A
  Firstmate reply that lands during the call is read by the model; after the call it opens a reading on the
  selected Voice Lane, including the chosen realtime voice. Realtime replies do not wait for Kokoro to load.
- The login token is only sent to the provider's HTTPS endpoint to mint a short-lived client secret, which then
  opens the WebSocket. It is never logged, copied or written. The Grok token lasts six hours; when it has
  expired, the app runs `grok models` once so the Grok CLI renews its own login.
- A missing or expired login, no network, a rejected response, a lost connection or a microphone failure
  is explained on screen. The on-device voice takes over when it is available.

### Speech models

| Choice | Model | Notes |
| --- | --- | --- |
| Parakeet Realtime (320 ms), the default | `parakeet-realtime-eou-120m` | Streaming, with an end-of-utterance head |
| Parakeet Realtime (160 ms) | same, 160 ms chunks | Lower latency, slightly less accurate |
| Parakeet TDT v2 (English) | `parakeet-tdt-0.6b-v2` | Larger offline model; live text refreshes twice a second |
| Fluid Speech Pro (English), the default when installed | `fluid-parakeet-pro` | FluidVoice's Parakeet TDT v3 fine-tune, read in place from FluidVoice's folder; never downloaded, changed or deleted by this app |

Silero VAD runs alongside every model and ends the utterance after the silence threshold. If Fluid Speech Pro
fails to load, TDT v2 is used and the pill says so.

### End of turn

- **Silence** (default): the silence threshold, or the realtime model's end-of-utterance head. Silero VAD reads
  audio in 256 ms steps, so the 0.8 s setting actually ends a turn after about 1 s of quiet.
- **Smart Turn**: [Smart Turn v3.2](https://github.com/pipecat-ai/smart-turn) judges each pause from the voice
  itself; a turn it calls finished is sent then, and one it calls unfinished waits. The silence threshold stays
  a hard ceiling. The 8.7 MB int8 model runs through ONNX Runtime in about 20 ms per check and downloads on
  first use (or from Settings › Models). On test clips it sent finished sentences about 0.8 s sooner than
  Silence but cut off more mid-sentence pauses, so it is off by default.

## Privacy

- **On device**: voice detection ([Silero VAD](https://github.com/snakers4/silero-vad), MIT), speech recognition
  (NVIDIA Parakeet TDT v2, CC-BY-4.0; Parakeet Realtime, NVIDIA Open Model License) and the voice ([Kokoro 82M](https://huggingface.co/hexgrad/Kokoro-82M),
  Apache-2.0) run on the Apple Neural Engine through [FluidAudio](https://github.com/FluidInference/FluidAudio)
  (Apache-2.0, pinned to 0.17.7). Smart Turn (BSD-2-Clause) runs on the CPU. Microphone audio is processed in memory; notes sent to Firstmate are stored as local files.
- **Fast assistant**: your words, a short fleet summary and matching past-work excerpts and paths go to
  Anthropic through the Claude CLI on your own Claude Code login, the same as typing them into Claude Code.
- **Realtime lanes**: your voice is streamed to OpenAI or xAI for the length of a call. Off unless you choose a
  lane.
- **Firstmate**: notes and replies are local files in the firstmate home; no network.
- **Event log**: `~/Library/Logs/NotchVoice/events.jsonl` holds note and turn ids, decisions and millisecond
  timings only, never transcript or reply text.

## Models and where things live

Settings › **Models** lists every local model with its state, size on disk, licence and source, with
**Download** and **Delete** for the app's own copies. Downloads are pinned to one revision of each source,
show progress, and resume from the bytes already on disk if interrupted. Smart Turn is also checked by SHA-256.

- Models: `~/Library/Application Support/NotchVoice/Models`. FluidAudio keeps Kokoro's small English lexicon in
  its own shared cache, `~/.cache/fluidaudio`.
- Fluid Speech Pro: `~/Library/Application Support/FluidAudio/Models/fluid-parakeet-pro-coreml`, read-only.
- The assistant process runs in the empty folder `~/Library/Application Support/NotchVoice/Assistant`.
- Settings: the defaults domain of the bundle id.

The Application Support, Logs and defaults names keep `NotchVoice`, the project's original name, so earlier
installs keep their models and settings.

## How it talks to Firstmate

Only through the firstmate home's own `bin/fm-inbox.sh`, with `FM_HOME` set to the configured home:

- send: `fm-inbox.sh note --request-id <uuid> --json -- <text>`; exit 3 (saved but not announced) is repaired
  with `fm-inbox.sh announce --json <id>`.
- reply: polls `fm-inbox.sh receipts --after <cursor>` (local files, no network) twice a second until the reply
  timeout, then every 5 s, for the reply recorded against that note id.

Firstmate answers a voice note with `fm-inbox.sh reply <id> "<text>"`. The fast assistant receives the
fleet summary from `fm-bearings-snapshot.sh --json` and read-only past-work results from the app's scoped
`data/` reader; the model itself has no tools and changes nothing.

Claude Code sessions in that home can also ask you questions through Fleet Comms. With the optional
`AskUserQuestion` hook installed (see [CONTRIBUTING.md](../CONTRIBUTING.md#claude-question-cards)), each
question opens in the pill itself, on the same surface and at the same width as listening and replies:
numbered options with the recommended choice marked, a typed or dictated reply, and a page per question.
Long questions show three lines with a Show more toggle. Send returns the answers to that session and
shows "Sent to"; close the question, or let it time out, and the session's own terminal picker takes over.
A reply or a voice note that arrives meanwhile takes the pill first; the question returns when it is done.
