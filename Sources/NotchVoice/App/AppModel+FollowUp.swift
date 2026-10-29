//  AppModel+FollowUp.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import AVFoundation
import Foundation

extension AppModel {
    /// A realtime lane is hands-free inside a call; between calls, a reply spoken on-device still gets
    /// the window the setting asks for, so the owner can answer it.
    func scheduleFollowUp() {
        guard settings.keepListeningAfterReply, settings.autoDismissSeconds > 0 else { return }
        // Without the models there is nothing to listen with; the reply still leaves on its own.
        guard modelsReady else { return collapse(after: settings.autoDismissSeconds) }
        let shown = state
        // Defer until stop/barge-in and queued-reply handlers have changed state.
        Task { @MainActor [weak self] in
            guard let self, state == shown, !speaker.isSpeaking, queuedReplies.isEmpty else { return }
            beginFollowUp()
        }
    }

    private func beginFollowUp() {
        guard settings.keepListeningAfterReply, settings.autoDismissSeconds > 0 else { return }
        let source = followUpFeed()
        // Passive listening must never raise a permission prompt or begin later after approval.
        guard source is WavFileFeed || AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            collapse(after: settings.autoDismissSeconds)
            return
        }
        let began = Date()
        startListening(feed: source, notePrefix: source is WavFileFeed ? Self.testNotePrefix : "", followUp: true)
        guard isFollowUp else { return }
        EventLog.record("follow_up_opened")
        let window = settings.autoDismissSeconds
        followUpTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(window))
            guard let self, !Task.isCancelled, isFollowUp else { return }
            cancelListening()
            EventLog.record("follow_up_expired", ["mic_off_requested_ms": EventLog.milliseconds(from: began)])
        }
    }
}
