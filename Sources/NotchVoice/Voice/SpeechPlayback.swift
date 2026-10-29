//  SpeechPlayback.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/29/26.

import Foundation

/// A position in the words being played, independent of synthesis or transcript arrival.
struct SpeechPlayback: Equatable, Sendable {
    let id: UUID
    let text: String
    let utf16Offset: Int

    func displayOffset(in displayed: String) -> Int {
        let suffix = text.hasSuffix(SpokenSummary.detailsSuffix) ? SpokenSummary.detailsSuffix.utf16.count : 0
        let source = Self.words(in: text).filter { $0.offset < text.utf16.count - suffix }
        let target = Self.words(in: displayed)
        let changes = source.map(\.text).difference(from: target.map(\.text))
        var inserted: Set<Int> = []
        var removed: Set<Int> = []
        for change in changes {
            switch change {
            case let .insert(offset, _, _): inserted.insert(offset)
            case let .remove(offset, _, _): removed.insert(offset)
            }
        }
        let spoken = source.indices.filter { !inserted.contains($0) }
        let visible = target.indices.filter { !removed.contains($0) }
        var position = 0
        for (spokenIndex, visibleIndex) in zip(spoken, visible) {
            guard source[spokenIndex].offset <= utf16Offset else { break }
            position = target[visibleIndex].offset
        }
        return position
    }

    private static func words(in text: String) -> [(text: String, offset: Int)] {
        guard let regex = try? NSRegularExpression(pattern: #"[\p{L}\p{N}]+(?:['’][\p{L}\p{N}]+)*"#)
        else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return (String(text[range]).lowercased(), match.range.location)
        }
    }
}
