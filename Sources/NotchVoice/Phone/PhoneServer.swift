//  PhoneServer.swift
//  NotchVoice
//
//  Created by Michael Duong on 11/17/26.

import Foundation
import Network

/// Listens for one paired iPhone handset. The token in the first frame is the only credential; the link
/// is meant for a Tailscale or home network, and an unpaired connection is closed without an answer.
@MainActor
final class PhoneServer {
    private var listener: NWListener?
    private var socket: PhoneSocket?
    private var authenticated = false
    private let token: () -> String
    /// The utterance the phone is speaking right now.
    var feed: PhoneFeed?

    var onMessage: ((PhoneMessage) -> Void)?
    var onAudio: (([Float]) -> Void)?
    var onConnectionChange: ((Bool) -> Void)?

    var isConnected: Bool {
        authenticated && socket != nil
    }

    init(token: @escaping () -> String) {
        self.token = token
    }

    func start() {
        guard listener == nil else { return }
        let parameters = NWParameters.tcp
        parameters.defaultProtocolStack.applicationProtocols.insert(NWProtocolWebSocket.Options(), at: 0)
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
            guard message.kind == .hello, let sent = message.token, Self.matches(sent, token()) else {
                return drop()
            }
            authenticated = true
            onConnectionChange?(true)
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
        if wasConnected {
            onConnectionChange?(false)
        }
    }

    /// Constant-time comparison, so response timing says nothing about the token.
    nonisolated static func matches(_ sent: String, _ expected: String) -> Bool {
        let left = Array(sent.utf8), right = Array(expected.utf8)
        guard left.count == right.count, !right.isEmpty else { return false }
        return zip(left, right).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
