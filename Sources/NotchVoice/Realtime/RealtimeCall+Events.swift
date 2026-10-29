//  RealtimeCall+Events.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation

extension RealtimeCall {
    func handle(_ event: RealtimeWire.Event) {
        guard !ended, !handleOutreach(event) else { return }
        switch event {
        case .speechStarted:
            ownerStartedTalking()
        case .speechStopped:
            ownerStoppedTalking()
        case let .userTranscript(text):
            if !text.isEmpty, !audioQueued {
                delegate?.call(self, text: text)
            }
        case let .error(code):
            EventLog.record("realtime_error", ["lane": provider.id, "code": code])
            end(.requestRejected)
        default:
            handleResponse(event)
        }
    }

    private func handleResponse(_ event: RealtimeWire.Event) {
        switch event {
        case .responseCreated:
            responseActive = true
        case let .audioDelta(itemID, audio):
            play(audio, itemID: itemID)
        case let .transcriptDelta(text):
            spoken += text
            delegate?.call(self, text: spoken)
        case let .functionCall(callID, name, arguments):
            handleToolCall(callID: callID, name: name, arguments: arguments)
        case let .responseDone(status):
            responseActive = false
            if status == "failed" || status == "incomplete" {
                end(.responseFailed)
                return
            }
            if status != "completed" {
                EventLog.record("realtime_response_ended", ["lane": provider.id, "status": status])
            }
            continueAfterTools()
            if !responseActive, pendingTools == 0, !audioQueued {
                becameQuiet()
            }
        default:
            break
        }
    }

    /// Barge-in: the server cancels its answer; drop what is queued and say how much was heard.
    private func ownerStartedTalking() {
        lastActivity = Date()
        ownerTalking = true
        updateInstructionsIfChanged()
        if audioQueued, let playingItem {
            audio?.flush()
            audioQueued = false
            let playedMs = Int(Date().timeIntervalSince(playingItem.since) * 1000)
            socket?.send(RealtimeWire.truncate(itemID: playingItem.id, playedMs: playedMs))
            EventLog.record("realtime_barge_in", ["lane": provider.id, "turn_id": turn?.id ?? "none"])
        }
        playingItem = nil
        spoken = ""
        delegate?.call(self, phase: .listening)
    }

    private func ownerStoppedTalking() {
        ownerTalking = false
        lastActivity = Date()
        turn = RealtimeTurn(lastSpeech: lastSpeech.value ?? Date())
        turns += 1
    }

    private func play(_ audio: Data, itemID: String) {
        if playingItem?.id != itemID {
            playingItem = (itemID, Date())
        }
        if var turn, !turn.firstAudioLogged {
            turn.firstAudioLogged = true
            self.turn = turn
            EventLog.record("realtime_first_audio", [
                "lane": provider.id, "turn_id": turn.id,
                "end_of_speech_to_first_audio_ms": EventLog.milliseconds(from: turn.lastSpeech),
                "speech_stopped_to_first_audio_ms": EventLog.milliseconds(from: turn.stoppedAt)
            ])
        }
        if let announcing {
            self.announcing = nil
            EventLog.record("realtime_reply_first_audio", [
                "lane": provider.id, "note_id": announcing.noteID,
                "reply_seen_to_first_audio_ms": EventLog.milliseconds(from: announcing.seenAt)
            ])
        }
        if !audioQueued {
            audioQueued = true
            delegate?.call(self, phase: .speaking)
        }
        self.audio?.play(RealtimePCM.decode(audio))
    }

    func drained() {
        guard audioQueued else { return }
        audioQueued = false
        lastActivity = Date()
        EventLog.record("realtime_audio_drained", ["lane": provider.id])
        if outreachPlayback {
            beginConversation()
            return
        }
        if !responseActive {
            becameQuiet()
        }
    }

    private func becameQuiet() {
        playingItem = nil
        spoken = ""
        delegate?.call(self, phase: .listening)
        announceIfQuiet()
    }

    func announceIfQuiet() {
        guard !ended, outreach == nil || outreach?.completed == true,
              socket != nil, !responseActive, pendingTools == 0,
              !audioQueued, !announcements.isEmpty else { return }
        let delivery = announcements.removeFirst()
        announcing = delivery
        socket?.send(RealtimeWire.userText(RealtimePrompt.reply(delivery.body)))
        socket?.send(RealtimeWire.createResponse())
        responseActive = true
    }
}
