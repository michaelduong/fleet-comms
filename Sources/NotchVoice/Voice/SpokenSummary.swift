//  SpokenSummary.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation

/// The spoken version of a reply, with links, code and markdown removed: the whole of it,
/// or its opening sentence or two plus "Details on screen." when anything is left over.
enum SpokenSummary {
    static let detailsSuffix = "Details on screen."
    static let maxSpokenLength = 240

    static func make(from reply: String, readWholeReply: Bool = false) -> String {
        if readWholeReply {
            return whole(from: reply)
        }
        var dropped = false
        let prose = speakableProse(from: reply, dropped: &dropped)
        let sentences = splitSentences(prose)
        guard let first = sentences.first else {
            return dropped ? detailsSuffix : ""
        }

        var spoken = truncated(first, dropped: &dropped)
        var used = 1
        if sentences.count > 1, spoken.count + sentences[1].count + 1 <= maxSpokenLength {
            spoken += " " + sentences[1]
            used = 2
        }
        if dropped || sentences.count > used {
            spoken += " " + detailsSuffix
        }
        return spoken
    }

    static func whole(from reply: String) -> String {
        var dropped = false
        let prose = speakableProse(from: reply, dropped: &dropped)
        return prose.isEmpty && dropped ? detailsSuffix : prose
    }

    static func speakableProse(from text: String, dropped: inout Bool) -> String {
        var result = text
        result = removing(#"```[\s\S]*?(```|$)"#, in: result, dropped: &dropped)
        result = removing(#"`[^`\n]*`"#, in: result, dropped: &dropped)
        let linked = result.replacingOccurrences(
            of: #"!?\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression
        )
        if linked != result {
            dropped = true
        }
        result = linked
        result = removing(#"<?\b(https?://|www\.)[^\s>)]+>?"#, in: result, dropped: &dropped)

        let lines = result.components(separatedBy: .newlines).compactMap(cleanLine)
        return lines.joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+([.,;:!?])"#, with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    static func splitSentences(_ text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"(?:[^.!?]|[.!?](?!\s|$))+(?:[.!?]+|$)"#)
        else { return [text] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { text[$0].trimmingCharacters(in: .whitespaces) }
        }
        .filter { $0.rangeOfCharacter(from: .alphanumerics) != nil }
    }

    /// Strips markdown line syntax and closes lines without end punctuation, so a
    /// heading or list item becomes its own spoken sentence instead of running on.
    private static func cleanLine(_ line: String) -> String? {
        var cleaned = line
            .replacingOccurrences(of: #"^\s{0,3}(#{1,6}|>+|[-*+]|\d+[.)])\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[*_~|]+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard cleaned.rangeOfCharacter(from: .alphanumerics) != nil else { return nil }
        if let last = cleaned.last, !".!?:;,".contains(last) {
            cleaned += "."
        }
        return cleaned
    }

    private static func removing(_ pattern: String, in text: String, dropped: inout Bool) -> String {
        let replaced = text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        if replaced != text {
            dropped = true
        }
        return replaced
    }

    private static func truncated(_ sentence: String, dropped: inout Bool) -> String {
        guard sentence.count > maxSpokenLength else { return sentence }
        dropped = true
        let prefix = sentence.prefix(maxSpokenLength)
        let cut = prefix.lastIndex(of: " ").map { prefix[..<$0] } ?? prefix
        return cut.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces)) + "…"
    }
}
