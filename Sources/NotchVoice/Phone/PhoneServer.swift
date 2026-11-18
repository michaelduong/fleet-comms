//  PhoneServer.swift
//  NotchVoice
//
//  Created by Michael Duong on 11/17/26.

import Foundation
import Network

/// Listens for one paired iPhone handset. The link is TLS with a pre-shared key per phone, so a connection
/// only completes for a phone holding its key (or the one-time pairing code); anything else is closed.
@MainActor
final class PhoneServer {
    private var listener: NWListener?
    private var socket: PhoneSocket?
    private var authenticated = false
    private let pairings: PhonePairings
    private var phoneID: String?
    /// The utterance the phone is speaking right now.
    var feed: PhoneFeed?

    /// Hex Push to Talk token the phone last reported, kept so the Mac can wake a locked phone.
    private(set) var pttToken: String?
    private let apns = ApnsPushToTalk.load()

    var canWake: Bool {
        apns != nil && pttToken != nil
    }

    /// Pushes the phone awake and waits for it to reconnect; false when it never does.
    func wake() async -> Bool {
        if isConnected {
            return true
        }
        guard let apns, let pttToken, await apns.wake(token: pttToken) else { return false }
        for _ in 0 ..< 40 where !isConnected {
            try? await Task.sleep(for: .milliseconds(250))
        }
        return isConnected
    }

    var onMessage: ((PhoneMessage) -> Void)?
    var onAudio: (([Float]) -> Void)?
    var onConnectionChange: ((Bool) -> Void)?

    var isConnected: Bool {
        authenticated && socket != nil
    }

    init(pairings: PhonePairings) {
        self.pairings = pairings
    }

    func start() {
        guard listener == nil else { return }
        let parameters = PhoneTLS.parameters(pairings.credentials)
        guard let listener = try? NWListener(using: parameters, on: NWEndpoint.Port(rawValue: PhoneLink.port)!) else {
            Log.speech.error("Phone link could not listen on port \(PhoneLink.port)")
            return
        }
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.accept(connection) }
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
        drop()
    }

    /// Listens again with the current keys. A connected phone stays connected; use `drop(phone:)` to end one.
    func rebuildListener() {
        listener?.cancel()
        listener = nil
        start()
    }

    func drop(phone id: String) {
        if phoneID == id {
            drop()
        }
    }

    func send(_ message: PhoneMessage) {
        guard isConnected else { return }
        socket?.send(message)
    }

    func sendAudio(_ samples: [Float]) {
        guard isConnected else { return }
        socket?.sendAudio(samples)
    }

    private func accept(_ connection: NWConnection) {
        drop()
        let socket = PhoneSocket(connection: connection)
        socket.onMessage = { [weak self, weak socket] message in
            Task { @MainActor in
                guard let self, let socket, socket === self.socket else { return }
                self.handle(message)
            }
        }
        socket.onAudio = { [weak self, weak socket] data in
            Task { @MainActor in
                guard let self, let socket, socket === self.socket, self.authenticated else { return }
                self.onAudio?(PhoneLink.samples(data))
            }
        }
        socket.onClose = { [weak self, weak socket] in
            Task { @MainActor in
                guard let self, let socket, socket === self.socket else { return }
                self.drop()
            }
        }
        self.socket = socket
        socket.start()
    }

    private func handle(_ message: PhoneMessage) {
        guard authenticated else {
            switch message.kind {
            case .hello:
                // The TLS handshake already proved a key; the phone names which one so Remove can find it.
                guard let id = message.token, pairings.hasPhone(id) else { return drop() }
                phoneID = id
                authenticated = true
                onConnectionChange?(true)
            case .pair:
                guard let id = message.token, let claimed = pairings.claim(codeID: id) else { return drop() }
                var reply = PhoneMessage(.paired)
                reply.token = claimed.phone.id
                reply.text = Base64URL.encode(claimed.key)
                socket?.send(reply)
            default: drop()
            }
            return
        }
        if message.kind == .pttToken {
            pttToken = message.text
            return
        }
        onMessage?(message)
    }

    private func drop() {
        let wasConnected = isConnected
        socket?.onClose = nil
        socket?.close()
        socket = nil
        authenticated = false
        phoneID = nil
        if wasConnected {
            onConnectionChange?(false)
        }
    }
}
