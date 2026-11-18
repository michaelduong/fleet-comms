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

    // Intent: the encrypted link (FLC-24) connects only for a phone holding the key the Mac listens for.
    @Test func tlsLinkNeedsTheRightKey() async throws {
        let key = Data((0 ..< 32).map { _ in UInt8.random(in: .min ... .max) })
        // A fresh listener per attempt: the message stream ends once a read has timed out.
        let server = LoopbackServer(credentials: [.init(identity: "phone-1", key: key)])
        let port = try await server.start()
        defer { server.listener.cancel() }

        let wrong = PhoneSocket.client(
            host: "127.0.0.1",
            port: port,
            credential: .init(identity: "phone-1", key: Data(repeating: 1, count: 32))
        )
        defer { wrong.close() }
        wrong.start { wrong.send(PhoneMessage(.hello)) }
        #expect(await server.firstMessage(within: .seconds(2)) == nil)

        let second = LoopbackServer(credentials: [.init(identity: "phone-1", key: key)])
        let secondPort = try await second.start()
        defer { second.listener.cancel() }
        let right = PhoneSocket.client(
            host: "127.0.0.1",
            port: secondPort,
            credential: .init(identity: "phone-1", key: key)
        )
        defer { right.close() }
        right.start {
            var hello = PhoneMessage(.hello)
            hello.token = "phone-1"
            right.send(hello)
        }
        #expect(await second.firstMessage(within: .seconds(5))?.token == "phone-1")
    }

    // Intent: the QR carries a link the phone reads back exactly, and refuses anything else.
    @Test func pairingLinkRoundTrips() throws {
        let link = PhonePairingLink(
            name: "Studio Mac",
            hosts: ["100.64.1.2", "studio.local"],
            port: 47653,
            id: "a1b2c3d4",
            key: Data((0 ..< 16).map { UInt8($0) })
        )
        let url = try #require(link.url)
        #expect(PhonePairingLink(url.absoluteString) == link)
        #expect(PhonePairingLink("https://example.com/pair?v=1") == nil)
        #expect(PhonePairingLink("fleetcomms://pair?v=2&a=x&p=1&i=a&k=AAAAAAAAAAAAAAAAAAAAAA") == nil)
    }
}

@MainActor
struct PhonePairingsTests {
    private func make() -> PhonePairings {
        let suite = "pairings-\(UUID().uuidString)"
        return PhonePairings(defaults: UserDefaults(suiteName: suite)!, keys: MemoryKeyStore())
    }

    // Intent: a code pairs one phone once, within five minutes, and Remove deletes that phone's key.
    @Test func codeWorksOnceAndRemoveCutsOff() throws {
        let pairings = make()
        let code = pairings.beginPairing()
        #expect(pairings.claim(codeID: "wrong") == nil)
        let claimed = try #require(pairings.claim(codeID: code.id))
        #expect(claimed.key.count == 32)
        #expect(pairings.claim(codeID: code.id) == nil)
        #expect(pairings.credentials.map(\.identity) == [claimed.phone.id])
        pairings.remove(claimed.phone.id)
        #expect(pairings.credentials.isEmpty)
    }

    @Test func expiredCodeIsRefused() {
        let pairings = make()
        let code = pairings.beginPairing()
        #expect(pairings.claim(codeID: code.id, now: Date().addingTimeInterval(PhonePairings.codeLife + 1)) == nil)
    }
}

@MainActor
struct PhoneServerRestartTests {
    /// Intent (FLC-35): Pair iPhone restarts the listener; cancel-then-start lost the bind to "address in use"
    /// and left the Mac silently deaf. After many quick restarts the listener must still be accepting.
    @Test func repeatedRestartsKeepListening() async throws {
        let pairings = try PhonePairings(
            defaults: #require(UserDefaults(suiteName: "restart-\(UUID().uuidString)")),
            keys: MemoryKeyStore()
        )
        let port = UInt16.random(in: 49152 ... 60000)
        let server = PhoneServer(pairings: pairings, port: port)
        server.start()
        defer { server.stop() }
        for _ in 0 ..< 30 {
            server.rebuildListener()
            try await Task.sleep(for: .milliseconds(5))
        }
        for _ in 0 ..< 100 where !server.isListening {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(server.isListening)
    }

    /// Intent (FLC-35): the QR lists the local name before the Tailscale address, which can hang the handshake.
    @Test func localNameComesBeforeTailscale() {
        #expect(PhoneAddress.order(tailscale: "100.64.1.2", name: "studio.local") == ["studio.local", "100.64.1.2"])
        #expect(PhoneAddress.order(tailscale: nil, name: "studio.local") == ["studio.local"])
    }
}

/// A WebSocket listener on a free loopback port, set up like the Mac's phone server.
private final class LoopbackServer: @unchecked Sendable {
    let listener: NWListener
    private let queue = DispatchQueue(label: "phone-socket-test")
    private let (received, stream) = AsyncStream<PhoneMessage>.makeStream()
    /// The accepted socket only holds itself weakly, so the server keeps it.
    private var accepted: PhoneSocket?

    init(credentials: [PhoneTLS.Credential] = []) {
        let parameters: NWParameters
        if credentials.isEmpty {
            parameters = NWParameters.tcp
            parameters.defaultProtocolStack.applicationProtocols.insert(NWProtocolWebSocket.Options(), at: 0)
        } else {
            parameters = PhoneTLS.parameters(credentials)
        }
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
