//  SessionReplyReader.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation

/// Incremental JSONL reader. Only explicit end-of-turn text is eligible for speech.
actor SessionReplyReader {
    struct Reply: Sendable {
        let id: String
        let text: String
        var seenAt = Date()
    }

    static let voiceMarker = "[Fleet Comms voice request]"
    static func isNoOpAcknowledgement(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines)
        let normalized = String(String
            .UnicodeScalarView(trimmed.unicodeScalars.reversed().drop(while: { suffix.contains($0) }).reversed()))
        return ["captain, shipshape", "shipshape"].contains(normalized.lowercased())
    }

    private let directory: URL
    private let startedAt: Date
    private var cursors: [URL: Cursor] = [:]
    private var seen: Set<String> = []

    init(home: String, projectsRoot: URL? = nil, startedAt: Date = Date()) {
        let root = projectsRoot ?? URL(fileURLWithPath: NSHomeDirectory() + "/.claude/projects")
        let path = URL(fileURLWithPath: (home as NSString).expandingTildeInPath).standardized.path
        // Claude replaces every non-alphanumeric character in the working directory with '-'.
        let name = path.replacingOccurrences(of: "[^a-zA-Z0-9]", with: "-", options: .regularExpression)
        directory = root.appendingPathComponent(name)
        self.startedAt = startedAt
    }

    func poll() -> [Reply] {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: Array(keys), options: .skipsHiddenFiles
        ), let newest = files.filter({ $0.pathExtension == "jsonl" }).max(by: {
            modified($0) < modified($1)
        }) else { return [] }
        var cursor = cursors[newest] ?? Cursor()
        guard let handle = try? FileHandle(forReadingFrom: newest) else { return [] }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        if size < cursor.offset {
            cursor = Cursor()
        }
        try? handle.seek(toOffset: cursor.offset)
        var replies: [Reply] = []
        // Bound each read so a large transcript never blocks the main actor or allocates the whole file.
        while let chunk = try? handle.read(upToCount: 256 * 1024), !chunk.isEmpty {
            cursor.offset += UInt64(chunk.count)
            cursor.buffer.append(chunk)
            while let newline = cursor.buffer.firstIndex(of: 0x0A) {
                let line = cursor.buffer[..<newline]
                if let reply = cursor.consume(Data(line), since: startedAt), seen.insert(reply.id).inserted {
                    replies.append(reply)
                }
                cursor.buffer.removeSubrange(...newline)
            }
        }
        cursors[newest] = cursor
        return replies
    }

    private func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}

extension SessionReplyReader {
    struct Cursor {
        var offset: UInt64 = 0
        var buffer = Data()
        private var voiceTurn = false
        private var messageID: String?
        private var textParts: [String] = []

        mutating func consume(_ line: Data, since start: Date) -> Reply? {
            guard let record = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  record["isSidechain"] as? Bool != true else { return nil }
            let type = record["type"] as? String
            let message = record["message"] as? [String: Any]
            if type == "user", record["isMeta"] as? Bool != true, Self.isOwnerContent(message?["content"]) {
                voiceTurn = false
                messageID = nil
                textParts = []
            }
            if let message, let data = try? JSONSerialization.data(withJSONObject: message),
               let content = String(data: data, encoding: .utf8),
               content.contains(SessionReplyReader.voiceMarker) {
                voiceTurn = true
            }
            guard type == "assistant", let message,
                  let blocks = message["content"] as? [[String: Any]] else { return nil }
            let id = message["id"] as? String ?? record["uuid"] as? String ?? ""
            if id != messageID {
                messageID = id
                textParts = []
            }
            let parts = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }
            for part in parts where !textParts.contains(part) {
                textParts.append(part)
            }
            guard message["stop_reason"] as? String == "end_turn", !voiceTurn,
                  !blocks.contains(where: { $0["type"] as? String == "tool_use" }),
                  let stamp = record["timestamp"] as? String,
                  let date = Self.date(stamp), date > start, !id.isEmpty else { return nil }
            let text = textParts.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty || SessionReplyReader.isNoOpAcknowledgement(text) ? nil : Reply(
                id: id,
                text: text,
                seenAt: date
            )
        }

        private static func isOwnerContent(_ content: Any?) -> Bool {
            if content is String {
                return true
            }
            guard let blocks = content as? [[String: Any]],
                  !blocks.contains(where: { $0["type"] as? String == "tool_result" }) else { return false }
            return blocks.contains { $0["type"] as? String == "text" }
        }

        private static func date(_ value: String) -> Date? {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
        }
    }
}
