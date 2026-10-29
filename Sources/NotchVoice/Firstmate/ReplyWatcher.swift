//  ReplyWatcher.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation

/// Polls `fm-inbox.sh receipts` (local files only, no network) for replies to the
/// notes this app sent. Polls twice a second until a note's timeout, then every
/// few seconds so a slow reply is still picked up.
@MainActor
final class ReplyWatcher {
    struct Delivery {
        let noteID: String
        let body: String
        let seenAt: Date
    }

    var onReply: ((Delivery) -> Void)?
    var onTimeout: ((String) -> Void)?

    private var watched: [String: Date] = [:]
    private var timedOut: Set<String> = []
    private var cursor: String?
    private var pollTask: Task<Void, Never>?
    private let fastInterval: Duration = .milliseconds(500)
    private let slowInterval: Duration = .seconds(5)

    /// Moves the cursor to the newest reply before a note is sent, so polls only
    /// read replies recorded after it. `receipts` pages replies 20 at a time.
    func primeCursor(inbox: FirstmateInbox) async {
        guard watched.isEmpty else { return }
        for _ in 0 ..< 100 {
            guard let page = try? await inbox.receipts(after: cursor) else { return }
            if !page.replyCursor.isEmpty {
                cursor = page.replyCursor
            }
            if page.replies.count < Self.receiptsReplyBound {
                return
            }
        }
    }

    private static let receiptsReplyBound = 20

    func watch(noteID: String, inbox: FirstmateInbox, timeout: TimeInterval) {
        watched[noteID] = Date().addingTimeInterval(timeout)
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            await self?.pollLoop(inbox: inbox)
        }
    }

    private func pollLoop(inbox: FirstmateInbox) async {
        while !Task.isCancelled, !watched.isEmpty {
            await pollOnce(inbox: inbox)
            checkTimeouts()
            let interval = watched.keys.allSatisfy(timedOut.contains) ? slowInterval : fastInterval
            try? await Task.sleep(for: interval)
        }
        pollTask = nil
    }

    private func pollOnce(inbox: FirstmateInbox) async {
        guard let page = try? await inbox.receipts(after: cursor) else { return }
        let seenAt = Date()
        for reply in page.replies where watched[reply.id] != nil {
            watched[reply.id] = nil
            timedOut.remove(reply.id)
            onReply?(Delivery(noteID: reply.id, body: reply.body, seenAt: seenAt))
        }
        if !page.replyCursor.isEmpty {
            cursor = page.replyCursor
        }
    }

    private func checkTimeouts() {
        let now = Date()
        for (noteID, deadline) in watched where deadline <= now && !timedOut.contains(noteID) {
            timedOut.insert(noteID)
            onTimeout?(noteID)
        }
    }
}
