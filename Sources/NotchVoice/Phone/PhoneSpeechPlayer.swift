//  PhoneSpeechPlayer.swift
//  NotchVoice
//
//  Created by Michael Duong on 11/17/26.

import FluidAudio
import Foundation

/// Plays a reply on the phone: each synthesized sentence goes through the radio kernel and over the link,
/// and the Mac waits out the sentence's duration so its own state follows what the phone is saying.
@MainActor
final class PhoneSpeechPlayer {
    private let server: PhoneServer
    private let renderer = PhoneRadioRenderer()

    init(server: PhoneServer) {
        self.server = server
    }

    var isAvailable: Bool {
        server.isConnected || server.canWake
    }

    func stop() {
        server.send(PhoneMessage(.stopSpeech))
    }

    func play(
        _ parts: [String], synthesize: @escaping @Sendable (String) async throws -> [Float],
        onStart: () -> Void, onPartPlayed: (Int) -> Void
    ) async throws {
        guard await server.wake() else { throw PhoneWakeError.unreachable }
        var speech = PhoneMessage(.speech)
        speech.text = parts.joined(separator: " ")
        server.send(speech)
        renderer.begin()
        var offset = 0
        var next = Task { try await synthesize(parts[0]) }
        for (index, part) in parts.enumerated() {
            let samples = try await next.value
            try Task.checkCancellation()
            if index + 1 < parts.count {
                let following = parts[index + 1]
                next = Task { try await synthesize(following) }
            }
            if index == 0 {
                onStart()
            }
            try await send(renderer.render(samples), start: offset, length: part.utf16.count)
            offset += part.utf16.count + 1
            onPartPlayed(offset - 1)
        }
        try await send(renderer.finish(), start: offset, length: 0)
        server.send(PhoneMessage(.speechEnd))
    }

    private func send(_ samples: [Float], start: Int, length: Int) async throws {
        guard !samples.isEmpty else { return }
        var part = PhoneMessage(.part)
        part.start = start
        part.length = length
        server.send(part)
        server.sendAudio(samples)
        try await Task.sleep(for: .seconds(Double(samples.count) / PhoneLink.speechRate))
    }
}

extension PhoneSpeechPlayer {
    func play(
        _ parts: [String], with kokoro: KokoroAneManager, speed: Float, id: UUID,
        progress: ((SpeechPlayback?) -> Void)?
    ) async throws {
        let text = parts.joined(separator: " ")
        try await play(
            parts, synthesize: { try await kokoro.synthesizeDetailed(text: $0, speed: speed).samples },
            onStart: {}, onPartPlayed: { progress?(SpeechPlayback(id: id, text: text, utf16Offset: $0)) }
        )
    }
}

enum PhoneWakeError: Error { case unreachable }
