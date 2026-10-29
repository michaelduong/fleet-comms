//  AssistantConversation.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation

/// Short rolling memory, kept in memory only: the last few exchanges (repeated to a fresh
/// process) and first-mate replies the assistant has not been told about yet.
struct AssistantConversation {
    static let maxExchanges = 6
    static let maxReplyLength = 600
    static let idleReset: TimeInterval = 15 * 60

    private(set) var recent: [AssistantTurnInput.Exchange] = []
    private var unseenReplies: [String] = []
    private var lastTurnAt: Date?

    /// True once the owner has been quiet long enough that the old thread should not carry over.
    func isIdleExpired(now: Date = Date()) -> Bool {
        guard let lastTurnAt else { return false }
        return now.timeIntervalSince(lastTurnAt) > Self.idleReset
    }

    mutating func reset() {
        recent = []
        unseenReplies = []
        lastTurnAt = nil
    }

    @MainActor mutating func input(ownerSaid: String, context: FleetContext) -> AssistantTurnInput {
        defer { unseenReplies = [] }
        return AssistantTurnInput(
            ownerSaid: ownerSaid,
            fleetContext: (context.ageSeconds ?? .max) > context.staleAfterSeconds ? nil : context.summary,
            contextAgeSeconds: context.ageSeconds,
            recent: recent,
            firstMateReplies: unseenReplies,
            staleAfterSeconds: context.staleAfterSeconds
        )
    }

    mutating func record(owner: String, assistant: String) {
        recent.append(.init(owner: owner, assistant: assistant))
        recent = Array(recent.suffix(Self.maxExchanges))
        lastTurnAt = Date()
    }

    mutating func noteFirstMateReply(_ body: String) {
        var dropped = false
        let prose = SpokenSummary.speakableProse(from: body, dropped: &dropped)
        unseenReplies.append(String(prose.prefix(Self.maxReplyLength)))
        unseenReplies = Array(unseenReplies.suffix(3))
    }
}
