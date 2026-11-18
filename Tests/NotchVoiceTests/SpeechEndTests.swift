//  SpeechEndTests.swift
//  NotchVoiceTests
//
//  Created by Michael Duong on 11/18/26.

@testable import NotchVoice
import Testing

/// Intent: the lock screen follows a long reply to its last sentence (FLC-38).
struct SpeechEndTests {
    @Test func emptyQueueBetweenSentencesIsNotTheEnd() {
        #expect(!SpeechEnd.shouldEnd(speechEnded: false, pendingBuffers: 0))
    }

    @Test func speechEndWithAudioLeftWaits() {
        #expect(!SpeechEnd.shouldEnd(speechEnded: true, pendingBuffers: 2))
    }

    @Test func speechEndWithEmptyQueueEnds() {
        #expect(SpeechEnd.shouldEnd(speechEnded: true, pendingBuffers: 0))
    }
}
