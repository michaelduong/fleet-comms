//  RealtimeCall+Outreach.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import AVFoundation
import Foundation

extension RealtimeCall {
    func handleOutreach(_ event: RealtimeWire.Event) -> Bool {
        guard !ended, let outreach, !outreach.completed else { return false }
        guard !outreachPlayback else { return true }
        do {
            if let samples = try outreach.consume(event) {
                outreachPlayback = true
                audioQueued = true
                delegate?.call(self, phase: .speaking)
                watchOutreach(seconds: Double(samples.count) / Double(RealtimeWire.sampleRate) + 5)
                audio?.play(samples, onStart: { [weak self] in
                    Task { @MainActor in
                        guard let self, !self.ended else { return }
                        EventLog.record("session_reply_first_audio", [
                            "turn_id": outreach.reply.id, "lane": self.provider.id,
                            "message_to_first_audio_ms": EventLog.milliseconds(from: outreach.reply.seenAt)
                        ])
                    }
                }, onFailure: { [weak self] _ in
                    Task { @MainActor in self?.end(.audioFailed) }
                })
            }
        } catch {
            end(RealtimeError.from(error))
        }
        return true
    }

    func startOutputAudio() {
        let audio = makeAudio()
        self.audio = audio
        audio.start(onInput: nil, onFailure: { [weak self] _ in
            Task { @MainActor in self?.end(.audioFailed) }
        })
    }

    func makeAudio() -> RealtimeAudio {
        RealtimeAudio(onProgress: { [weak self] fraction in
            Task { @MainActor in
                guard let self, !self.ended, let outreach = self.outreach, !outreach.completed else { return }
                let text = outreach.readingText
                self.delegate?.call(self, playback: SpeechPlayback(
                    id: self.speechID, text: text, utf16Offset: Int(Double(text.utf16.count) * fraction)
                ))
            }
        }, onDrained: { [weak self] in
            Task { @MainActor in self?.drained() }
        })
    }

    func beginConversation() {
        guard !ended, let socket else { return }
        if let outreach {
            outreach.completed = true
            outreachPlayback = false
            outreachDeadline?.cancel()
            audio?.stop()
            audio = nil
            EventLog.record("outreach_reading_finished", ["lane": provider.id, "turn_id": outreach.reply.id])
        }
        if outreach != nil, case .microphone = source,
           AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
            end(.microphonePermission)
            return
        }
        updateInstructionsIfChanged()
        startAudio(socket)
        delegate?.call(self, phase: .listening)
        lastActivity = Date()
        watchForIdle()
        EventLog.record("realtime_input_started", ["lane": provider.id, "source": source.logName])
        announceIfQuiet()
    }

    func watchOutreach(seconds: Double) {
        outreachDeadline?.cancel()
        outreachDeadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            self?.end(.timedOut)
        }
    }
}
