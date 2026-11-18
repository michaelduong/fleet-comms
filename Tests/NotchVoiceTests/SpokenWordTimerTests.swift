//  SpokenWordTimerTests.swift
//  NotchVoiceTests
//
//  Created by Michael Duong on 11/17/26.

import Foundation
@testable import NotchVoice
import Testing

/// Intent: the phone shows each word when the voice starts it (FLC-25). The durations follow Kokoro's layout:
/// index 0 is the start token, duration i + 1 belongs to phoneme i, the last is the end token.
struct SpokenWordTimerTests {
    @Test func startsComeFromPhonemeDurations() throws {
        // "lock screen" as "lɑk skɹin": 9 phonemes + a space.
        let phonemes = "lɑk skɹin"
        let durations: [Int32] = [11] + Array(repeating: 3, count: phonemes.count) + [2]
        let words = try #require(SpokenWordTimer.words(
            text: "lock screen", phonemes: phonemes, durations: durations, normalizedText: nil
        ))
        #expect(words.map(\.start) == [0, 5])
        #expect(words.map(\.length) == [4, 6])
        #expect(words[0].sample == 11 * 600)
        #expect(words[1].sample == (11 + 4 * 3) * 600)
    }

    @Test func hyphenatedWordAlignsThroughNormalizedText() throws {
        // "lock-screen" is one written word but two spoken groups; the word starts with its first group.
        let phonemes = "lɑk skɹin ˈoʊ"
        let durations: [Int32] = [1] + Array(repeating: 2, count: phonemes.count) + [1]
        let words = try #require(SpokenWordTimer.words(
            text: "lock-screen on", phonemes: phonemes, durations: durations, normalizedText: "lock screen on"
        ))
        #expect(words.map(\.start) == [0, 12])
        #expect(words[0].sample == 600)
    }

    @Test func numberSpokenAsSeveralWordsKeepsLaterWordsInStep() throws {
        // "PR 42 merged" is spoken "P R forty two merged".
        let phonemes = "pi ɑɹ fˈɔɹɾi tˈu mˈɜɹdʒd"
        let durations: [Int32] = [1] + Array(repeating: 1, count: phonemes.count) + [1]
        let words = try #require(SpokenWordTimer.words(
            text: "PR 42 merged", phonemes: phonemes, durations: durations,
            normalizedText: "P R forty two merged"
        ))
        #expect(words.count == 3)
        #expect(words[2].sample == (1 + "pi ɑɹ fˈɔɹɾi tˈu ".count) * 600)
    }

    @Test func mismatchGivesNoTimes() {
        #expect(SpokenWordTimer.words(
            text: "a b c",
            phonemes: "ɑ bi",
            durations: [1, 1, 1, 1, 1, 1],
            normalizedText: nil
        ) == nil)
        #expect(SpokenWordTimer.words(text: "a b", phonemes: "ɑ bi", durations: [1], normalizedText: nil) == nil)
    }

    @Test func revealShowsWordsWhoseStartPlayed() {
        let words = [PhoneWord(start: 0, length: 4, sample: 100), PhoneWord(start: 5, length: 3, sample: 500)]
        #expect(SpokenReveal.offset(words: words, playedSamples: 50) == nil)
        #expect(SpokenReveal.offset(words: words, playedSamples: 100) == 4)
        #expect(SpokenReveal.offset(words: words, playedSamples: 900) == 8)
    }

    @Test func guessSnapsToWholeWords() {
        let text = "hello wonderful world"
        #expect(SpokenReveal.guessOffset(in: text, range: 0 ..< 21, fraction: 0) == 0)
        #expect(SpokenReveal.guessOffset(in: text, range: 0 ..< 21, fraction: 0.4) == 15)
        #expect(SpokenReveal.guessOffset(in: text, range: 0 ..< 21, fraction: 1) == 21)
    }

    @Test func partMessageRoundTripsWordsAndOldMessagesDecode() throws {
        var part = PhoneMessage(.part)
        part.words = [PhoneWord(start: 0, length: 5, sample: 1200)]
        let decoded = try JSONDecoder().decode(PhoneMessage.self, from: JSONEncoder().encode(part))
        #expect(decoded == part)
        let old = try JSONDecoder().decode(PhoneMessage.self, from: Data(#"{"t":"part","start":0,"length":5}"#.utf8))
        #expect(old.words == nil)
    }
}
