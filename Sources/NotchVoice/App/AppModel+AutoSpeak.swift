//  AppModel+AutoSpeak.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation

extension AppModel {
    func configureAutoSpeak() {
        #if DEBUG
            if case let .wav(url) = outreachSource {
                followUpFeed = { WavFileFeed(url: url) }
            }
        #endif
        stopAutoSpeech()
        sessionReplyTask?.cancel()
        sessionReplyTask = nil
        autoSpeakReplies.removeAll()
        guard settings.speakFirstmateReplies, !settings.firstmateHome.isEmpty else { return }
        let reader = SessionReplyReader(home: settings.firstmateHome, projectsRoot: outreachProofProjectsRoot)
        sessionReplyTask = Task { [weak self] in
            while !Task.isCancelled {
                let replies = await reader.poll()
                guard !Task.isCancelled else { return }
                for reply in replies {
                    self?.receiveSessionReply(reply)
                }
                self?.presentAutoSpeakReply()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private var outreachProofProjectsRoot: URL? {
        #if DEBUG
            guard Bundle.main.bundleIdentifier?.hasPrefix("com.fleetcomms.proof.") == true,
                  let path = DeveloperActions.argument("--outreach-projects-root") else { return nil }
            return URL(fileURLWithPath: path)
        #else
            return nil
        #endif
    }

    func receiveSessionReply(_ reply: SessionReplyReader.Reply) {
        EventLog.record("session_reply_seen", ["turn_id": reply.id])
        // Full replies finish before another reply starts; summary mode keeps replacement behavior.
        autoSpeakReplies.append(reply)
        if case .reply = state, speaker.isSpeaking, !settings.readWholeReply {
            stopAutoSpeech()
        }
        presentAutoSpeakReply()
    }

    func presentAutoSpeakReply() {
        guard let reply = autoSpeakReplies.first,
              settings.outreachVoice.provider != nil || speaker.isLoaded,
              !speaker.isSpeaking, !isAutoSpeaking,
              feed == nil, call == nil else { return }
        switch state {
        case .listening, .sending, .thinking, .preparing, .call: return
        default: break
        }
        autoSpeakReplies.removeFirst()
        collapseTask?.cancel()
        isAutoSpeaking = true
        let token = UUID()
        autoSpeakID = token
        state = .reply(text: reply.text, speaking: true, from: .firstMate)
        if let provider = settings.outreachVoice.provider {
            beginRealtimeCall(provider: provider, source: outreachSource, notePrefix: "", outreach: .init(reply: reply))
        } else {
            speakLocalOutreach(reply, token: token, verbatim: false)
        }
    }

    var outreachSource: RealtimeCall.Source {
        if let outreachSourceOverride {
            return outreachSourceOverride
        }
        #if DEBUG
            if Bundle.main.bundleIdentifier?.hasPrefix("com.fleetcomms.proof.") == true,
               let path = DeveloperActions.argument("--outreach-reply-wav") {
                return .wav(URL(fileURLWithPath: path))
            }
        #endif
        return .microphone
    }

    func stopAutoSpeech() {
        guard isAutoSpeaking else { return }
        autoSpeakID = nil
        isAutoSpeaking = false
        if call?.outreach != nil {
            endCallQuietly()
        }
        speaker.stop()
    }

    func outreachCallEnded(_ call: RealtimeCall, error: RealtimeError?) -> Bool {
        guard let outreach = call.outreach else { return false }
        if let error {
            EventLog.record("outreach_fallback", ["lane": call.provider.id, "reason": error.code])
            let useLocalVoice = !outreach.completed && speaker.isLoaded
            let next = useLocalVoice ? "Reading with the on-device voice." : "The reply is shown below."
            let notice = "\(call.provider.title) \(error.reason(call.provider)). \(next)"
            state = .reply(text: notice + "\n\n" + outreach.reply.text, speaking: useLocalVoice, from: .firstMate)
            if useLocalVoice, let token = autoSpeakID {
                speakLocalOutreach(outreach.reply, token: token, verbatim: true, spokenText: outreach.spokenText)
                return true
            }
            isAutoSpeaking = false
            autoSpeakID = nil
            return true
        }
        isAutoSpeaking = false
        autoSpeakID = nil
        return false
    }

    private func speakLocalOutreach(
        _ reply: SessionReplyReader.Reply, token: UUID, verbatim: Bool, spokenText: String? = nil
    ) {
        let spoken = spokenText ?? (verbatim ? reply.text : SpokenSummary.make(
            from: reply.text, readWholeReply: settings.readWholeReply
        ))
        speaker.speak(spoken, onStart: { [weak self] in
            self?.outreachStarted(reply, token: token, lane: "kokoro")
        }, onFinish: { [weak self] in self?.finishOutreach(reply, token: token) })
    }

    private func outreachStarted(_ reply: SessionReplyReader.Reply, token: UUID, lane: String) {
        guard autoSpeakID == token else { return }
        EventLog.record("session_reply_first_audio", [
            "turn_id": reply.id, "lane": lane,
            "message_to_first_audio_ms": EventLog.milliseconds(from: reply.seenAt)
        ])
    }

    private func finishOutreach(_ reply: SessionReplyReader.Reply, token: UUID) {
        guard autoSpeakID == token else { return }
        autoSpeakID = nil
        isAutoSpeaking = false
        EventLog.record("session_reply_finished", ["turn_id": reply.id])
        if case let .reply(text, _, _) = state {
            state = .reply(text: text, speaking: false, from: .firstMate)
            scheduleAutoDismiss()
        }
        Task { @MainActor in self.presentQueuedReply() }
    }
}
