//  AppModel+Realtime.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation

extension AppModel {
    /// Hotkey, pill or WAV feed: a realtime call on a realtime lane, one utterance on-device otherwise.
    func startTalking(_ source: RealtimeCall.Source, notePrefix: String) {
        guard let provider = settings.voiceLane.provider else {
            return startListening(feed: source.onDeviceFeed, notePrefix: notePrefix)
        }
        if case .microphone = source, !microphoneAllowed() {
            return
        }
        stopAutoSpeech()
        beginRealtimeCall(provider: provider, source: source, notePrefix: notePrefix)
    }

    func beginRealtimeCall(
        provider: RealtimeProvider, source: RealtimeCall.Source, notePrefix: String,
        outreach: RealtimeOutreach? = nil
    ) {
        endCallQuietly()
        collapseTask?.cancel()
        speaker.stop()
        transcript = ""
        speechPlayback = nil
        level = 0
        callNotePrefix = notePrefix
        fleet.refreshIfStale()
        let fleet = fleet
        let dataDirectory = settings.firstmateHome.isEmpty ? nil :
            URL(fileURLWithPath: settings.firstmateHome).appendingPathComponent("data", isDirectory: true)
        let call = RealtimeCall(
            provider: provider, voice: settings.realtimeVoice(provider), source: source,
            silenceSeconds: settings.silenceSeconds,
            idleHangUp: outreach == nil ? settings.hangUpAfterQuietSeconds : settings.outreachHangUpSeconds,
            outreach: outreach, dataDirectory: dataDirectory
        ) {
            // Older than 5 minutes counts as unavailable, the same rule as the fast assistant.
            let fresh = (fleet.ageSeconds ?? .max) <= 300
            let prompt = RealtimePrompt.instructions(
                fleetSummary: fresh ? fleet.summary : nil, refreshedAt: fleet.refreshedAt
            )
            guard let outreach else { return prompt }
            return prompt + "\nThe first mate outreach you just read aloud was:\n" + outreach.reply.text
        }
        call.delegate = self
        self.call = call
        EventLog.record("realtime_call_started", ["lane": provider.id, "source": source.logName])
        call.start()
    }

    func hangUp() {
        call?.end()
    }

    /// Ends a call without the usual hand-back, e.g. when the lane changes or a new call starts.
    func endCallQuietly() {
        guard let old = call else { return }
        call = nil
        speechPlayback = nil
        if old.outreach != nil {
            isAutoSpeaking = false
            autoSpeakID = nil
        }
        queuedReplies.insert(contentsOf: old.announcements, at: 0)
        old.end()
    }

    /// Says why the realtime lane stopped, then carries on with the on-device lane: listening again
    /// on the mic, or feeding the WAV that never reached the server.
    private func fallBack(from call: RealtimeCall, _ error: RealtimeError) {
        EventLog.record("realtime_fallback", ["lane": call.provider.id, "reason": error.code])
        let line = "\(call.provider.title) \(error.reason(call.provider)), so I'm using the on-device assistant."
        let resume: RealtimeCall.Source? = switch call.source {
        case .microphone: .microphone
        case .wav: call.socket == nil ? call.source : nil
        }
        let shown = NotchState.reply(text: line, speaking: true, from: .assistant)
        state = shown
        speaker.speak(line, onStart: {}, onFinish: { [weak self] in
            guard let self, state == shown else { return }
            if let resume, modelsReady {
                startListening(feed: resume.onDeviceFeed, notePrefix: callNotePrefix)
            } else {
                state = .reply(text: line, speaking: false, from: .assistant)
                scheduleAutoDismiss()
            }
        })
    }
}

extension AppModel: RealtimeCallDelegate {
    func call(_ call: RealtimeCall, phase: CallPhase) {
        guard call === self.call else { return }
        state = .call(phase)
    }

    func call(_ call: RealtimeCall, level: Float) {
        guard call === self.call, state == .call(.listening) else { return }
        self.level = level
    }

    func call(_ call: RealtimeCall, text: String) {
        guard call === self.call else { return }
        transcript = text
    }

    func call(_ call: RealtimeCall, playback: SpeechPlayback) {
        guard call === self.call else { return }
        speechPlayback = playback
    }

    func call(_ call: RealtimeCall, handOff request: String, endpoint: Endpoint) async -> String? {
        try? await fileNote(callNotePrefix + request, endpoint: endpoint)
    }

    func call(_ call: RealtimeCall, endedWith error: RealtimeError?) {
        guard call === self.call else { return }
        self.call = nil
        speechPlayback = nil
        queuedReplies.insert(contentsOf: call.announcements, at: 0)
        level = 0
        if outreachCallEnded(call, error: error) {
            return
        }
        if let error {
            return fallBack(from: call, error)
        }
        state = pendingReplies > 0 ? .waiting : .idle
        presentQueuedReply()
    }
}

extension RealtimeCall.Source {
    @MainActor var onDeviceFeed: any AudioFeed {
        switch self {
        case .microphone: MicrophoneFeed()
        case let .wav(url): WavFileFeed(url: url)
        }
    }

    var logName: String {
        switch self {
        case .microphone: "mic"
        case .wav: "wav"
        }
    }
}
