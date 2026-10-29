//  AppModel+Assistant.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation

extension AppModel {
    static let handoffLine = "Passed to Firstmate. I'll tell you when it answers."
    static let fallbackLine = "The quick assistant didn't answer, so I sent that straight to Firstmate."

    enum AfterSpeech {
        /// Leave the answer on screen, then fold away after the auto-dismiss delay.
        case linger
        /// Fold back to waiting for the first mate's reply.
        case wait
    }

    func configureAssistant() {
        let old = assistant
        assistant = nil
        Task { await old?.shutdown() }
        conversation.reset()
        configureFleetSchedule()
        if settings.assistantEnabled || settings.voiceLane.provider != nil {
            fleet.start(home: settings.firstmateHome)
        } else {
            fleet.stop()
        }
        guard settings.assistantEnabled else { return }
        let dataDirectory = settings.firstmateHome.isEmpty ? nil :
            URL(fileURLWithPath: settings.firstmateHome).appendingPathComponent("data", isDirectory: true)
        let assistant = ClaudeAssistant(
            executable: settings.resolvedClaudePath, model: settings.messengerModel, dataDirectory: dataDirectory
        )
        self.assistant = assistant
        Task { await assistant.warmUp() }
    }

    func configureFleetSchedule() {
        fleet.configure(active: settings.fleetActiveRefresh, idle: settings.fleetIdleRefresh)
    }

    /// With the assistant on, it answers or hands off; with it off, or when it fails, the
    /// words go straight to the first mate as a note. Talking over "Thinking…" drops the turn.
    func route(_ text: String, notePrefix: String, endpoint: Endpoint) async {
        guard settings.assistantEnabled, let assistant else {
            await send(notePrefix + text, endpoint: endpoint)
            return
        }
        if conversation.isIdleExpired() {
            conversation.reset()
            await assistant.recycle()
        }
        state = .thinking
        fleet.refreshIfStale()
        let turnID = String(UUID().uuidString.prefix(8))
        let input = conversation.input(ownerSaid: text, context: fleet)
        do {
            let turn = try await assistant.ask(input)
            logTurn(turn, id: turnID, endpoint: endpoint, contextAge: input.contextAgeSeconds)
            guard state == .thinking else { return }
            conversation.record(owner: text, assistant: turn.reply.speak)
            if turn.reply.handoff {
                await handOff(notePrefix + text, lead: turn.reply.speak, turnID: turnID, endpoint: endpoint)
            } else {
                speakAssistant(turn.reply.speak, turnID: turnID, endpoint: endpoint, then: .linger)
            }
        } catch {
            let reason = (error as? AssistantError)?.code ?? "error"
            EventLog.record("assistant_failed", ["turn_id": turnID, "reason": reason])
            guard state == .thinking else { return }
            state = .sending
            guard await send(notePrefix + text, endpoint: endpoint) != nil else { return }
            let shown = Self.fallbackLine + "\n\n" + error.localizedDescription
            speakAssistant(Self.fallbackLine, shown: shown, turnID: turnID, endpoint: endpoint, then: .wait)
        }
    }

    private func handOff(_ note: String, lead: String, turnID: String, endpoint: Endpoint) async {
        state = .sending
        guard let noteID = await send(note, endpoint: endpoint) else { return }
        EventLog.record("assistant_handoff", ["turn_id": turnID, "note_id": noteID])
        let line = [lead, Self.handoffLine].filter { !$0.isEmpty }.joined(separator: " ")
        speakAssistant(line, turnID: turnID, endpoint: endpoint, then: .wait)
    }

    func speakAssistant(
        _ spoken: String, shown: String? = nil, turnID: String, endpoint: Endpoint, then after: AfterSpeech
    ) {
        collapseTask?.cancel()
        let text = shown ?? spoken
        let speakingState = NotchState.reply(text: text, speaking: true, from: .assistant)
        state = speakingState
        speaker.speak(
            spoken,
            onStart: {
                EventLog.record("assistant_first_audio", [
                    "turn_id": turnID,
                    "end_of_speech_to_first_audio_ms": EventLog.milliseconds(from: endpoint.lastSpeech)
                ])
            },
            onFinish: { [weak self] in
                guard let self else { return }
                EventLog.record("assistant_spoken", ["turn_id": turnID])
                if state == speakingState {
                    switch after {
                    case .linger:
                        state = .reply(text: text, speaking: false, from: .assistant)
                        scheduleAutoDismiss()
                    case .wait:
                        state = pendingReplies > 0 ? .waiting : .idle
                        scheduleFollowUp()
                    }
                }
                // Deferred: a barge-in stops speech and starts listening in the same call.
                Task { @MainActor in self.presentQueuedReply() }
            }
        )
    }

    private func logTurn(_ turn: ClaudeAssistant.Turn, id: String, endpoint: Endpoint, contextAge: Int?) {
        var fields = [
            "turn_id": id,
            "handoff": String(turn.reply.handoff),
            "total_ms": String(turn.totalMs),
            "process_turn": String(turn.processTurn),
            "end_of_speech_to_answer_ms": EventLog.milliseconds(from: endpoint.lastSpeech),
            "context_age_s": contextAge.map(String.init) ?? "none"
        ]
        fields["first_token_ms"] = turn.firstTokenMs.map(String.init)
        EventLog.record("assistant_turn", fields)
    }
}
