//  InboxRecords.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation

/// `fm-inbox.sh note --json` output (schema fm-inbox-note.v1).
struct NoteReceipt: Decodable, Sendable {
    let outcome: String
    let id: String
}

/// The slice of `fm-inbox.sh receipts` (schema fm-inbox-receipts.v1) this app reads.
struct ReceiptsPage: Decodable, Sendable {
    struct Reply: Decodable, Sendable {
        let id: String
        let body: String
        let cursor: String
    }

    let replies: [Reply]
    let replyCursor: String

    enum CodingKeys: String, CodingKey {
        case replies
        case replyCursor = "reply_cursor"
    }
}

enum InboxError: LocalizedError {
    case homeNotSet
    case scriptMissing(String)
    case failed(command: String, status: Int32, message: String)
    case unreadable(command: String)

    var errorDescription: String? {
        switch self {
        case .homeNotSet:
            "No Firstmate home is set. Choose one in Settings › General."
        case let .scriptMissing(path):
            "Inbox script not found at \(path). Check Settings › General."
        case let .failed(command, status, message):
            "fm-inbox.sh \(command) failed (exit \(status)): \(message)"
        case let .unreadable(command):
            "fm-inbox.sh \(command) returned output this app cannot read."
        }
    }
}
