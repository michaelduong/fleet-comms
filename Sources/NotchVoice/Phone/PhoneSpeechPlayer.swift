//  PhoneSpeechPlayer.swift
//  NotchVoice
//
//  Created by Michael Duong on 11/17/26.

import FluidAudio
import Foundation

/// Plays a reply on the phone: each synthesized sentence goes through the radio kernel and over the link,
/// and the Mac waits out the sentence's duration so its own state follows what the phone is saying.
@MainActor
protocol PhoneTransport: AnyObject {
    var isConnected: Bool { get }
    var canWake: Bool { get }
    func wake() async -> Bool
    func send(_ message: PhoneMessage)
    func sendAudio(_ samples: [Float])
}

extension PhoneServer: PhoneTransport {}

@MainActor
final class PhoneSpeechPlayer {
    private let server: PhoneTransport
    private let renderer = PhoneRadioRenderer()
    /// When the audio sent so far finishes playing. Pacing against one deadline keeps timer lateness from adding up.
    private var deadline = ContinuousClock.now
    private static let lead = Duration.milliseconds(500)

    init(server: PhoneTransport) {
        self.server = server
    }

    var isAvailable: Bool {
        server.isConnected || server.canWake
    }

    func stop() {
        server.send(PhoneMessage(.stopSpeech))
    }

    func play(
        _ parts: [String], synthesize: @escaping @Sendable (String) async throws -> PhoneSentence,
        from first: Int = 0, onStart: () -> Void, onPartPlayed: (Int) -> Void
    ) async throws {
        guard await server.wake() else { throw PhoneWakeError.unreachable }
        var speech = PhoneMessage(.speech)
        speech.text = parts.joined(separator: " ")
        server.send(speech)
        renderer.begin()
        deadline = ContinuousClock.now
        var offset = parts[..<first].reduce(0) { $0 + $1.utf16.count + 1 }
        var next = Task { try await synthesize(parts[first]) }
        defer { next.cancel() }
        for (index, part) in parts.enumerated() where index >= first {
            let sentence = try await next.value
            let samples = sentence.samples
            try Task.checkCancellation()
            if index + 1 < parts.count {
                let following = parts[index + 1]
                next = Task { try await synthesize(following) }
            }
            if index == first {
                onStart()
            }
            do {
                try await send(renderer.render(samples), start: offset, length: part.utf16.count, words: sentence.words)
            } catch let error as PhoneLinkLost {
                // This sentence reached nobody; the Mac says it, so the caller resumes at its index.
                throw PhoneLinkLost(resumeAt: index, reason: error.reason)
            }
            offset += part.utf16.count + 1
            onPartPlayed(offset - 1)
        }
        do {
            try await send(renderer.finish(), start: offset, length: 0)
        } catch is PhoneLinkLost {
            return // Every sentence was already sent; only the radio tail is lost.
        }
        server.send(PhoneMessage(.speechEnd))
    }

    private func send(_ samples: [Float], start: Int, length: Int, words: [PhoneWord]? = nil) async throws {
        guard !samples.isEmpty else { return }
        // The iPhone resets the link whenever the app leaves the screen, and send drops silently when it is gone.
        guard server.isConnected else { throw PhoneLinkLost(resumeAt: 0, reason: "link down") }
        var part = PhoneMessage(.part)
        part.start = start
        part.length = length
        part.words = words
        server.send(part)
        server.sendAudio(samples)
        deadline += .seconds(Double(samples.count) / PhoneLink.speechRate)
        try await Task.sleep(until: deadline - Self.lead, tolerance: .zero)
        guard server.isConnected else { throw PhoneLinkLost(resumeAt: 0, reason: "link dropped") }
    }
}

extension PhoneSpeechPlayer {
    func play(
        _ parts: [String], with kokoro: KokoroAneManager, speed: Float, id: UUID,
        from first: Int = 0, progress: ((SpeechPlayback?) -> Void)?
    ) async throws {
        let text = parts.joined(separator: " ")
        try await play(
            parts, synthesize: { part in
                let result = try await kokoro.synthesizeDetailed(text: part, speed: speed)
                let words = SpokenWordTimer.words(
                    text: part, phonemes: result.phonemes, durations: result.predictedDurations,
                    normalizedText: result.normalizedText
                )
                return PhoneSentence(samples: result.samples, words: words)
            },
            from: first, onStart: {}, onPartPlayed: { progress?(SpeechPlayback(id: id, text: text, utf16Offset: $0)) }
        )
    }
}

/// One synthesized sentence and, when the voice's timing could be matched to the text, its word starts.
struct PhoneSentence: Sendable {
    var samples: [Float]
    var words: [PhoneWord]?
}

enum PhoneWakeError: Error { case unreachable }

/// The link dropped while a reply was being sent; `resumeAt` is the first sentence the phone may not have heard.
struct PhoneLinkLost: Error {
    var resumeAt: Int
    var reason: String
}
