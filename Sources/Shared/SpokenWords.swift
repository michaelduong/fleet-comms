//  SpokenWords.swift
//  NotchVoice
//
//  Created by Michael Duong on 11/17/26.

import Foundation

/// One written word of a sentence and when the voice starts it, in samples from the sentence's first sample.
struct PhoneWord: Codable, Equatable, Sendable {
    /// UTF-16 start and length of the word inside the sentence text.
    var start: Int
    var length: Int
    /// Samples at 24 kHz before the voice starts the word.
    var sample: Int

    private enum CodingKeys: String, CodingKey { case start = "s", length = "l", sample = "a" }
}

struct WrittenWord {
    let word: String
    let start: Int
    let length: Int
}

/// Turns Kokoro's phonemes and per-phoneme durations into the start of each written word.
enum SpokenWordTimer {
    /// Samples per duration frame, from the vocoder's hop (measured: audio length = 600 × summed durations).
    static let samplesPerFrame = 600

    /// Nil when the sound groups cannot be matched to the written words with confidence.
    static func words(
        text: String, phonemes: String, durations: [Int32], normalizedText: String?
    ) -> [PhoneWord]? {
        let chars = Array(phonemes)
        // Index 0 is the start token and the last the end token; duration i + 1 belongs to phoneme i.
        guard durations.count == chars.count + 2 else { return nil }
        var starts: [Int] = []
        var frame = Int(durations[0])
        var inGroup = false
        for (index, char) in chars.enumerated() {
            if char == " " {
                inGroup = false
            } else if !inGroup {
                inGroup = true
                starts.append(frame)
            }
            frame += Int(durations[index + 1])
        }
        let written = wordRanges(in: text)
        guard !written.isEmpty, !starts.isEmpty else { return nil }
        let owners = alignment(
            written: written.map(\.word),
            spoken: normalizedText.map { wordRanges(in: $0).map(\.word) },
            groups: starts.count
        )
        guard let owners else { return nil }
        return zip(written, owners).map { PhoneWord(
            start: $0.0.start,
            length: $0.0.length,
            sample: starts[$0.1] * samplesPerFrame
        ) }
    }

    /// For each written word, the index of the sound group it starts with.
    private static func alignment(written: [String], spoken: [String]?, groups: Int) -> [Int]? {
        if written.count == groups {
            return Array(0 ..< groups)
        }
        guard let spoken, spoken.count == groups else { return nil }
        let key: (String) -> String = { $0.lowercased().filter { $0.isLetter || $0.isNumber } }
        let target = spoken.map(key)
        var owners: [Int] = []
        var next = 0
        for (index, word) in written.enumerated() {
            guard next < groups else { return nil }
            owners.append(next)
            let wanted = key(word)
            // Take spoken words while they spell the written one ("lock screen" for "lock-screen").
            var joined = target[next]
            var take = 1
            while joined != wanted, wanted.hasPrefix(joined), next + take < groups {
                joined += target[next + take]
                take += 1
            }
            if joined != wanted {
                // Numbers and abbreviations: take spoken words up to where the next written word begins.
                take = 1
                if index + 1 < written.count,
                   let later = target[(next + 1)...].firstIndex(of: key(written[index + 1])) {
                    take = later - next
                } else if index + 1 == written.count {
                    take = groups - next
                }
            }
            next += take
        }
        return next == groups ? owners : nil
    }

    /// Whitespace-separated words with their UTF-16 ranges.
    static func wordRanges(in text: String) -> [WrittenWord] {
        var result: [WrittenWord] = []
        var index = text.startIndex
        while index < text.endIndex {
            if text[index].isWhitespace {
                index = text.index(after: index)
                continue
            }
            let end = text[index...].firstIndex(where: \.isWhitespace) ?? text.endIndex
            result.append(WrittenWord(
                word: String(text[index ..< end]),
                start: text.utf16.distance(from: text.startIndex, to: index),
                length: text.utf16[index ..< end].count
            ))
            index = end
        }
        return result
    }
}

/// Which part of the reply the phone shows, from what the speaker has played.
enum SpokenReveal {
    /// End of the last word whose start has played, or nil before the first. `words` are in reply
    /// coordinates (UTF-16 offsets in the reply, samples since the reply's first sample), in order.
    static func offset(words: [PhoneWord], playedSamples: Int) -> Int? {
        words.last(where: { $0.sample <= playedSamples }).map { $0.start + $0.length }
    }

    /// The letter-position guess for a sentence without word times, snapped to whole words.
    static func guessOffset(in text: String, range: Range<Int>, fraction: Double) -> Int {
        let raw = range.lowerBound + Int(Double(range.count) * min(1, max(0, fraction)))
        guard fraction > 0 else { return range.lowerBound }
        if raw >= range.upperBound {
            return range.upperBound
        }
        // Reveal the word the guess has entered, in full.
        let utf16 = Array(text.utf16)
        var end = raw
        while end < utf16.count, end < range.upperBound, !isSpace(utf16[end]) {
            end += 1
        }
        return end
    }

    private static func isSpace(_ unit: UInt16) -> Bool {
        unit == 0x20 || unit == 0x0A || unit == 0x09
    }
}
