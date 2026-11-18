//  PhoneSocketTests.swift
//  NotchVoice
//
//  Created by Michael Duong on 11/17/26.

import Foundation
import Network
@testable import NotchVoice
import Testing

struct PhoneSocketTests {
    // Intent: the handset's client socket must reach the Mac's WebSocket listener; built from a host and port
    // it never connected and the phone reported that the Mac did not answer.
    @Test func clientReachesWebSocketListener() async throws {
        let server = LoopbackServer()
        let port = try await server.start()
        defer { server.listener.cancel() }
        let client = PhoneSocket.client(host: "127.0.0.1", port: port)
        defer { client.close() }
        client.start {
            var hello = PhoneMessage(.hello)
            hello.token = "pairing-code"
            client.send(hello)
        }

        let first = await server.firstMessage(within: .seconds(5))
        #expect(first?.kind == .hello)
        #expect(first?.token == "pairing-code")
    }
}

/// A WebSocket listener on a free loopback port, set up like the Mac's phone server.
private final class LoopbackServer: @unchecked Sendable {
    let listener: NWListener
    private let queue = DispatchQueue(label: "phone-socket-test")
    private let (received, stream) = AsyncStream<PhoneMessage>.makeStream()
    /// The accepted socket only holds itself weakly, so the server keeps it.
    private var accepted: PhoneSocket?

    init() {
        let parameters = NWParameters.tcp
        parameters.defaultProtocolStack.applicationProtocols.insert(NWProtocolWebSocket.Options(), at: 0)
        listener = try! NWListener(using: parameters) // swiftlint:disable:this force_try
    }

    func start() async throws -> UInt16 {
        listener.newConnectionHandler = { [self] connection in
            let socket = PhoneSocket(connection: connection, queue: queue)
            socket.onMessage = { [stream] in stream.yield($0) }
            accepted = socket
            socket.start()
        }
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [listener] state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    continuation.resume(returning: listener.port?.rawValue ?? 0)
                case let .failed(error):
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: queue)
        }
    }

    func firstMessage(within limit: Duration) async -> PhoneMessage? {
        let received = received
        return await withTaskGroup(of: PhoneMessage?.self) { group in
            group.addTask { await received.first { _ in true } }
            group.addTask {
                try? await Task.sleep(for: limit)
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }
}
