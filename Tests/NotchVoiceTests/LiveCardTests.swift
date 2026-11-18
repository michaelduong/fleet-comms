//  LiveCardTests.swift
//  NotchVoiceTests
//
//  Created by Michael Duong on 11/18/26.

@testable import NotchVoice
import Testing

/// Intent: the lock screen keeps the first mate's last spoken sentence after it stops (FLC-26).
struct LiveCardTests {
    private let reply = "Okay, I changed the voice. Curious how it sounds now."

    @Test func speakingShowsTheSentenceBeingSpoken() {
        let sentence = LiveCard.sentence(phase: .speaking, reply: reply, offset: 30, held: "")
        #expect(sentence == "Curious how it sounds now.")
    }

    @Test func afterSpeakingTheLastSentenceStays() {
        let held = "Curious how it sounds now."
        #expect(LiveCard.sentence(phase: .idle, reply: reply, offset: reply.utf16.count, held: held) == held)
        #expect(LiveCard.sentence(phase: .thinking, reply: "", offset: 0, held: held) == held)
    }

    @Test func blankMomentKeepsTheHeldSentence() {
        #expect(LiveCard.sentence(phase: .speaking, reply: "", offset: 0, held: "Hi.") == "Hi.")
    }
}
