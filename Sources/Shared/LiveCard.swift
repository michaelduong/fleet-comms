//  LiveCard.swift
//  FleetCommsPhone
//
//  Created by Michael Duong on 11/18/26.

import Foundation

/// What the lock-screen card says. Pure so a test can pin it: only the first mate's words ever show, and the
/// last sentence it said stays after it stops.
enum LiveCard {
    enum Phase: String, Codable, Hashable { case listening, thinking, speaking, idle }

    static func phase(isTalking: Bool, isSpeaking: Bool, macState: String) -> Phase {
        isTalking ? .listening : isSpeaking ? .speaking
            : (macState == "thinking" || macState == "sending") ? .thinking : .idle
    }

    /// The sentence being spoken at `offset` (UTF-16 units into `reply`), whole.
    static func spokenSentence(reply: String, offset: Int) -> String {
        let utf16 = Array(reply.utf16)
        let upTo = min(utf16.count, max(0, offset))
        let before = String(utf16CodeUnits: Array(utf16[..<upTo]), count: upTo)
        let start = before.lastIndex(where: { ".!?".contains($0) }).map { before.index(after: $0) } ?? before
            .startIndex
        let rest = String(utf16CodeUnits: Array(utf16[upTo...]), count: utf16.count - upTo)
        let end = rest.firstIndex(where: { ".!?".contains($0) }).map { rest.index(after: $0) } ?? rest.endIndex
        return (before[start...] + rest[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The sentence to show: the one being spoken while speaking, else the last one said. A blank moment
    /// (such as the radio tail) keeps what was there.
    static func sentence(phase: Phase, reply: String, offset: Int, held: String) -> String {
        guard phase == .speaking else { return held }
        let current = spokenSentence(reply: reply, offset: offset)
        return current.isEmpty ? held : current
    }

    /// Whether the island should pop open by itself: once per reply, when the voice starts on the phone, only
    /// while Fleet Comms is off screen and the phone is unlocked. Replies the Mac plays never reach here.
    static func shouldAlert(phase: Phase, alreadyAlerted: Bool, sentence: String, appOnScreen: Bool,
                            unlocked: Bool) -> Bool {
        phase == .speaking && !alreadyAlerted && !sentence.isEmpty && !appOnScreen && unlocked
    }
}
