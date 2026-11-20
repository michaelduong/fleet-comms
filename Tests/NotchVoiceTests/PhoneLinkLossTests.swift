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

    /// Intent (FLC-43): a phone that connects mid-reply, or after the link was lost, resumes at a sentence offset.
    @Test func playResumesFromGivenSentence() async throws {
        let transport = FakeTransport()
        let player = PhoneSpeechPlayer(server: transport)
        var played: [Int] = []
        try await player.play(
            ["One.", "Two.", "Three."],
            synthesize: { _ in PhoneSentence(samples: [Float](repeating: 0.1, count: 2400), words: nil) },
            from: 1, onStart: {}, onPartPlayed: { played.append($0) }
        )
        #expect(played == [9, 16])
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
