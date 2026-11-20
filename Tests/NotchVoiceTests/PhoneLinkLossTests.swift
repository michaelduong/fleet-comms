//  PhoneLinkLossTests.swift
//  NotchVoice
//
//  Created by Michael Duong on 11/19/26.

@testable import NotchVoice
import Testing

@MainActor
struct PhoneLinkLossTests {
    /// Intent (FLC-43): a reply whose link drops mid-way was paced to nobody and heard nowhere; the player must
    /// stop with the sentence to resume on so the Mac can say the rest.
    @Test func linkDropMidReplyReportsWhereToResume() async throws {
        let transport = FakeTransport()
        let player = PhoneSpeechPlayer(server: transport)
        var played: [Int] = []
        transport.onAudio = {
            if transport.audioFrames == 1 {
                transport.isConnected = false
            }
        }
        do {
            try await player.play(
                ["One.", "Two.", "Three."],
                synthesize: { _ in PhoneSentence(samples: [Float](repeating: 0.1, count: 2400), words: nil) },
                onStart: {}, onPartPlayed: { played.append($0) }
            )
            Issue.record("play finished although the link dropped")
        } catch let lost as PhoneLinkLost {
            #expect(lost.resumeAt == 0)
            #expect(transport.audioFrames == 1)
            #expect(played.isEmpty)
        }
    }

    /// Intent (FLC-49 finding 1): the real iPhone leaves silently and the Mac learns of it from the reset that answers
    /// its next send; it must resume at the sentence that was playing, not one sentence late.
    @Test func dropNoticedOnNextSendResumesAtTheUnheardSentence() async throws {
        let transport = FakeTransport()
        let player = PhoneSpeechPlayer(server: transport)
        var sends = 0
        transport.onAudio = {
            sends += 1
            if sends == 2 { transport.isConnected = false } // the reset answers sentence 1's send
        }
        do {
            try await player.play(
                ["One.", "Two.", "Three."],
                synthesize: { _ in PhoneSentence(samples: [Float](repeating: 0.1, count: 2400), words: nil) },
                onStart: {}, onPartPlayed: { _ in }
            )
            Issue.record("play finished although the link dropped")
        } catch let lost as PhoneLinkLost {
            #expect(lost.resumeAt == 0)
        }
    }

    /// Intent (FLC-49 finding 1): a drop during the pacing wait ends it at once instead of at the sentence's deadline.
    @Test func dropDuringPacingEndsTheWaitPromptly() async throws {
        let transport = FakeTransport()
        let player = PhoneSpeechPlayer(server: transport)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            transport.isConnected = false
        }
        let start = ContinuousClock.now
        do {
            try await player.play(
                ["One one one.", "Two two two."],
                synthesize: { _ in PhoneSentence(samples: [Float](repeating: 0.1, count: 24000), words: nil) },
                onStart: {}, onPartPlayed: { _ in }
            )
            Issue.record("play finished although the link dropped")
        } catch let lost as PhoneLinkLost {
            #expect(lost.resumeAt == 0)
            #expect(ContinuousClock.now - start < .milliseconds(700))
        }
    }

    /// Intent (FLC-49 finding 3): a phone that cannot be woken must fail with PhoneWakeError, which the speaker
    /// answers by saying the whole reply on the Mac.
    @Test func failedWakeThrowsSoTheMacCanSpeak() async throws {
        let transport = FakeTransport()
        transport.isConnected = false
        let player = PhoneSpeechPlayer(server: transport)
        await #expect(throws: PhoneWakeError.self) {
            try await player.play(
                ["One."], synthesize: { _ in PhoneSentence(samples: [], words: nil) },
                onStart: {}, onPartPlayed: { _ in }
            )
        }
    }
}

@MainActor
private final class FakeTransport: PhoneTransport {
    var isConnected = true
    let canWake = false
    var audioFrames = 0
    var onAudio: (() -> Void)?
    func wake() async -> Bool {
        isConnected
    }

    func send(_: PhoneMessage) {}
    func sendAudio(_: [Float]) {
        audioFrames += 1
        onAudio?()
    }
}
