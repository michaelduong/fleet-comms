//  RealtimeSocket.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation

/// One realtime WebSocket. Sends go through a single ordered queue, so audio chunks yielded from
/// the capture thread reach the server in order.
final class RealtimeSocket: Sendable {
    static let connectTimeout: Duration = .seconds(10)

    private let task: URLSessionWebSocketTask
    private let outbound: AsyncStream<String>.Continuation

    private init(task: URLSessionWebSocketTask) {
        self.task = task
        let (stream, continuation) = AsyncStream.makeStream(of: String.self, bufferingPolicy: .unbounded)
        outbound = continuation
        Task.detached { [task] in
            for await text in stream {
                do {
                    try await task.send(.string(text))
                } catch {
                    return
                }
            }
        }
    }

    /// Mints a short-lived client secret with the subscription login, then opens the socket with
    /// it and waits for `session.created`.
    static func connect(_ provider: RealtimeProvider) async throws -> RealtimeSocket {
        let login = try await SubscriptionLogin.token(for: provider)
        let secret = try await mint(provider, login: login)
        var request = URLRequest(url: provider.socketURL)
        request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        let task = session.webSocketTask(with: request)
        task.maximumMessageSize = 16 * 1024 * 1024
        task.resume()
        let expired = ThreadSafeBox(false)
        let watchdog = Task {
            try await Task.sleep(for: connectTimeout)
            expired.value = true
            task.cancel(with: .goingAway, reason: nil)
        }
        defer { watchdog.cancel() }
        do {
            let first = try await task.receive()
            guard case let .string(text) = first, RealtimeWire.parse(text) == .sessionCreated else {
                throw RealtimeError.connectionLost
            }
        } catch {
            task.cancel(with: .goingAway, reason: nil)
            throw expired.value ? RealtimeError.timedOut : RealtimeError.from(error)
        }
        return RealtimeSocket(task: task)
    }

    func send(_ text: String) {
        outbound.yield(text)
    }

    /// Server events until the socket closes; a close is thrown as `connectionLost`.
    func events() -> AsyncThrowingStream<RealtimeWire.Event, Error> {
        AsyncThrowingStream { [task] continuation in
            let reader = Task {
                while !Task.isCancelled {
                    do {
                        if case let .string(text) = try await task.receive() {
                            continuation.yield(RealtimeWire.parse(text))
                        }
                    } catch {
                        continuation.finish(throwing: RealtimeError.connectionLost)
                        return
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in reader.cancel() }
        }
    }

    func close() {
        outbound.finish()
        task.cancel(with: .normalClosure, reason: nil)
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        return URLSession(configuration: configuration)
    }()

    private static func mint(_ provider: RealtimeProvider, login: SubscriptionLogin.Token) async throws -> String {
        var request = URLRequest(url: provider.mintURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(login.bearer)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: provider.mintBody)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // Nothing was connected yet, so any transport failure means the service can't be reached.
            let failure = RealtimeError.from(error)
            throw failure == .connectionLost ? RealtimeError.offline : failure
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200: break
        case 401: throw RealtimeError.loginExpired
        case 403: throw RealtimeError.notEntitled
        default: throw RealtimeError.mintFailed(status)
        }
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let nested = object?["client_secret"] as? [String: Any]
        guard let secret = object?["value"] as? String ?? nested?["value"] as? String else {
            throw RealtimeError.mintFailed(status)
        }
        return secret
    }
}
