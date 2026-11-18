//  AppModel+Phone.swift
//  NotchVoice
//
//  Created by Michael Duong on 11/17/26.

import Foundation

/// The Mac as the phone's base station: the handset sends microphone audio and gets state, words and
/// reply speech back. Everything between, including the Assistant setting, is the desktop's own path.
extension AppModel {
    var phoneConnected: Bool {
        phoneServer?.isConnected ?? false
    }

    func configurePhone() {
        phoneServer?.stop()
        phoneServer = nil
        speaker.phone = nil
        guard settings.phone.enabled else { return }
        let server = PhoneServer(token: { [weak settings] in settings?.phone.token ?? "" })
        server.onConnectionChange = { [weak self] connected in self?.phoneConnectionChanged(connected) }
        server.onMessage = { [weak self] in self?.phoneMessage($0) }
        server.onAudio = { [weak self] in self?.phoneServer?.feed?.receive($0) }
        server.start()
        phoneServer = server
        speaker.phone = PhoneSpeechPlayer(server: server)
    }

    private func phoneConnectionChanged(_ connected: Bool) {
        EventLog.record(connected ? "phone_connected" : "phone_disconnected")
        if connected {
            var ready = PhoneMessage(.ready)
            ready.assistant = settings.assistantEnabled
            phoneServer?.send(ready)
            phoneStateChanged()
        } else if phoneServer?.feed != nil {
            phoneServer?.feed = nil
            cancelListening()
        }
    }

    private func phoneMessage(_ message: PhoneMessage) {
        switch message.kind {
        case .start: phoneStart()
        case .release: phoneServer?.feed?.release()
        case .cancel:
            guard phoneServer?.feed != nil else { return }
            phoneServer?.feed = nil
            cancelListening()
        case .stopSpeech: speaker.stop()
        default: break
        }
    }

    private func phoneStart() {
        switch state {
        case .listening, .preparing, .sending, .thinking, .call: return
        default: break
        }
        speaker.stop()
        let feed = PhoneFeed()
        phoneServer?.feed = feed
        startListening(feed: feed, notePrefix: "")
        if state != .listening {
            phoneServer?.feed = nil
        }
    }

    func phoneTranscriptChanged() {
        guard phoneServer?.feed != nil else { return }
        var message = PhoneMessage(.transcript)
        message.text = transcript
        phoneServer?.send(message)
    }

    func phoneStateChanged() {
        guard phoneConnected else { return }
        if state != .listening {
            phoneServer?.feed = nil
        }
        var message = PhoneMessage(.state)
        switch state {
        case .listening: message.state = "listening"
        case .sending: message.state = "sending"
        case .thinking: message.state = "thinking"
        case .waiting, .stillWorking: message.state = "waiting"
        case .reply: message.state = "reply"
        case let .message(text):
            message.state = "message"
            message.text = text
        case .preparing: message.state = "preparing"
        default: message.state = "idle"
        }
        phoneServer?.send(message)
    }
}
