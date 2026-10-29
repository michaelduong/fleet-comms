//  FirstmateInbox.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation

/// Talks to the first mate only through its home's `fm-inbox.sh`: `note` to send,
/// `announce` to repair a saved-but-unannounced note, `receipts` to read replies.
struct FirstmateInbox: Sendable {
    let home: String
    let script: String

    /// Exit 3 from `note --json` means the note is on disk but its wake was not
    /// appended; `announce` repairs that without saving a second note.
    static let savedButNotAnnounced: Int32 = 3

    func sendNote(_ text: String, requestID: UUID) async throws -> NoteReceipt {
        let args = ["note", "--request-id", requestID.uuidString, "--json", "--", text]
        let result = try await run(args)
        guard result.status == 0 || result.status == Self.savedButNotAnnounced else {
            throw InboxError.failed(command: "note", status: result.status, message: result.stderr)
        }
        let receipt = try decode(NoteReceipt.self, from: result.stdout, command: "note")
        if result.status == Self.savedButNotAnnounced {
            try await announce(receipt.id)
        }
        return receipt
    }

    func announce(_ noteID: String) async throws {
        let result = try await run(["announce", "--json", noteID])
        guard result.status == 0 else {
            throw InboxError.failed(command: "announce", status: result.status, message: result.stderr)
        }
    }

    func receipts(after cursor: String?) async throws -> ReceiptsPage {
        var args = ["receipts"]
        if let cursor, !cursor.isEmpty {
            args += ["--after", cursor]
        }
        let result = try await run(args)
        guard result.status == 0 else {
            throw InboxError.failed(command: "receipts", status: result.status, message: result.stderr)
        }
        return try decode(ReceiptsPage.self, from: result.stdout, command: "receipts")
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data, command: String) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw InboxError.unreadable(command: command)
        }
    }

    private func run(_ arguments: [String]) async throws -> ProcessResult {
        guard !home.isEmpty else { throw InboxError.homeNotSet }
        guard FileManager.default.isExecutableFile(atPath: script) else {
            throw InboxError.scriptMissing(script)
        }
        var environment = ProcessInfo.processInfo.environment
        environment["FM_HOME"] = home
        // A login-item launch gets a bare PATH; the script needs bash and python3.
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        return try await ProcessRunner.run(executable: script, arguments: arguments, environment: environment)
    }
}
