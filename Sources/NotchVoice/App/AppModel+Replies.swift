//  AppModel+Replies.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation

extension AppModel {
    /// Returns the note id, or nil after telling the owner, on screen and out loud, that it was not sent.
    @discardableResult
    func send(_ text: String, endpoint: Endpoint) async -> String? {
        do {
            let noteID = try await fileNote(text, endpoint: endpoint)
            if state == .sending {
                state = .waiting
            }
            return noteID
        } catch {
            show(message: "Not sent: \(error.localizedDescription)")
            speaker.speak("I couldn't send that to Firstmate.", onStart: {}, onFinish: {})
            return nil
        }
    }

    /// Files a note and starts watching for its reply; failures are logged and thrown.
    func fileNote(_ text: String, endpoint: Endpoint) async throws -> String {
        do {
            let receipt = try await inbox.sendNote(text + "\n\n" + SessionReplyReader.voiceMarker, requestID: UUID())
            let saved = Date()
            EventLog.record("note_saved", [
                "note_id": receipt.id,
                "outcome": receipt.outcome,
                "end_of_speech_to_saved_ms": EventLog.milliseconds(from: endpoint.lastSpeech, to: saved),
                "endpoint_to_saved_ms": EventLog.milliseconds(from: endpoint.detected, to: saved)
            ])
            pendingReplies += 1
            watcher.watch(noteID: receipt.id, inbox: inbox, timeout: settings.replyTimeoutSeconds)
            return receipt.id
        } catch {
            Log.inbox.error("Send failed: \(error.localizedDescription, privacy: .public)")
            EventLog.record("note_failed")
            throw error
        }
    }

    func receive(_ delivery: ReplyWatcher.Delivery) {
        pendingReplies = max(0, pendingReplies - 1)
        if isAutoSpeaking, call == nil, !settings.readWholeReply {
            stopAutoSpeech()
        }
        EventLog.record("reply_seen", ["note_id": delivery.noteID])
        if settings.assistantEnabled {
            conversation.noteFirstMateReply(delivery.body)
        }
        if let call {
            call.announce(delivery)
        } else if canPresentReply {
            present(delivery)
        } else {
            queuedReplies.append(delivery)
        }
    }

    func presentQueuedReply() {
        guard !queuedReplies.isEmpty, canPresentReply else {
            presentAutoSpeakReply()
            return
        }
        present(queuedReplies.removeFirst())
    }

    func replyTimedOut() {
        guard state == .waiting else { return }
        state = .stillWorking
        collapse(after: 3)
    }

    /// A reply waits while the owner is talking, the assistant is busy, or anything is being spoken.
    private var canPresentReply: Bool {
        switch state {
        case .listening, .sending, .thinking, .preparing, .call: false
        default: !speaker.isSpeaking && !isAutoSpeaking
        }
    }

    private func present(_ delivery: ReplyWatcher.Delivery) {
        collapseTask?.cancel()
        let text = delivery.body
        state = .reply(text: text, speaking: true, from: .firstMate)
        let body = SpokenSummary.make(from: text, readWholeReply: settings.readWholeReply)
        // With two voices in play, say whose reply this is.
        let spoken = settings.assistantEnabled ? "Firstmate replied. " + body : body
        if let provider = settings.voiceLane.provider {
            isAutoSpeaking = true
            autoSpeakID = UUID()
            beginRealtimeCall(
                provider: provider, source: outreachSource, notePrefix: "",
                outreach: .init(reply: .init(id: delivery.noteID, text: text), spokenText: spoken)
            )
            return
        }
        speaker.speak(
            spoken,
            onStart: {
                EventLog.record("first_audio", [
                    "note_id": delivery.noteID,
                    "reply_seen_to_first_audio_ms": EventLog.milliseconds(from: delivery.seenAt)
                ])
            },
            onFinish: { [weak self] in
                guard let self else { return }
                EventLog.record("reply_spoken", [
                    "note_id": delivery.noteID,
                    "sentences": String(ReplySpeaker.parts(of: spoken).count),
                    "seen_to_spoken_end_ms": EventLog.milliseconds(from: delivery.seenAt)
                ])
                if case let .reply(shown, _, _) = state, shown == text {
                    state = .reply(text: text, speaking: false, from: .firstMate)
                    scheduleAutoDismiss()
                }
                Task { @MainActor in self.presentQueuedReply() }
            }
        )
    }
}
