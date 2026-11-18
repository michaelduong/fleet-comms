//  PhoneSocket.swift
//  NotchVoice
//
//  Created by Michael Duong on 11/17/26.

import Foundation
import Network

/// One WebSocket connection carrying `PhoneMessage`s and raw sample frames; the same type serves both ends.
final class PhoneSocket: @unchecked Sendable {
    let connection: NWConnection
    private let queue: DispatchQueue
    var onMessage: (@Sendable (PhoneMessage) -> Void)?
    var onAudio: (@Sendable (Data) -> Void)?
    var onClose: (@Sendable () -> Void)?
    private var closed = false

    init(connection: NWConnection, queue: DispatchQueue = .main) {
        self.connection = connection
        self.queue = queue
    }

    static func client(host: String, port: UInt16) -> PhoneSocket {
        let parameters = NWParameters.tcp
        parameters.defaultProtocolStack.applicationProtocols.insert(NWProtocolWebSocket.Options(), at: 0)
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!,
            using: parameters
        )
        return PhoneSocket(connection: connection)
    }

    func start(onReady: (@Sendable () -> Void)? = nil) {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                onReady?()
                self?.receive()
            case .failed, .cancelled:
                self?.finish()
            default: break
            }
        }
        connection.start(queue: queue)
    }

    func send(_ message: PhoneMessage) {
        guard let data = try? JSONEncoder().encode(message) else { return }
        write(data, opcode: .text)
    }

    func sendAudio(_ samples: [Float]) {
        write(PhoneLink.data(samples), opcode: .binary)
    }

    func close() {
        connection.cancel()
        finish()
    }

    private func write(_ data: Data, opcode: NWProtocolWebSocket.Opcode) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: opcode)
        let context = NWConnection.ContentContext(identifier: "frame", metadata: [metadata])
        connection.send(content: data, contentContext: context, isComplete: true, completion: .idempotent)
    }

    private func receive() {
        connection.receiveMessage { [weak self] data, context, _, error in
            guard let self else { return }
            if let data, let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition)
                as? NWProtocolWebSocket.Metadata {
                switch metadata.opcode {
                case .text:
                    if let message = try? JSONDecoder().decode(PhoneMessage.self, from: data) {
                        onMessage?(message)
                    }
                case .binary: onAudio?(data)
                case .close: return close()
                default: break
                }
            }
            if error == nil {
                receive()
            } else {
                finish()
            }
        }
    }

    private func finish() {
        guard !closed else { return }
        closed = true
        onClose?()
    }
}
