//  Log.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation
import os

enum Log {
    static let app = Logger(subsystem: "io.github.michaelduong.fleetcomms", category: "app")
    static let speech = Logger(subsystem: "io.github.michaelduong.fleetcomms", category: "speech")
    static let inbox = Logger(subsystem: "io.github.michaelduong.fleetcomms", category: "inbox")
}

/// Timing events as JSON lines in ~/Library/Logs/NotchVoice/events.jsonl, used to
/// measure end-of-speech → note saved, assistant turns and reply seen → first audio.
/// Holds note and turn ids, handoff decisions and timings only, never transcript or reply text.
enum EventLog {
    static let url: URL = {
        #if DEBUG
            if let path = ProcessInfo.processInfo.environment["NOTCH_VOICE_EVENT_LOG"] {
                return URL(fileURLWithPath: path)
            }
        #endif
        let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/NotchVoice", isDirectory: true)
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        return logs.appendingPathComponent("events.jsonl")
    }()

    private static let queue = DispatchQueue(label: "io.github.michaelduong.fleetcomms.eventlog")

    static func record(_ event: String, _ fields: [String: String] = [:]) {
        var entry = fields
        entry["event"] = event
        entry["at_ms"] = String(Int64(Date().timeIntervalSince1970 * 1000))
        guard var line = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]) else { return }
        line.append(0x0A)
        let encoded = line
        queue.async {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(encoded)
                try? handle.close()
            } else {
                try? encoded.write(to: url)
            }
        }
        Log.app.info("event \(event, privacy: .public) \(fields.description, privacy: .public)")
    }

    static func milliseconds(from start: Date, to end: Date = Date()) -> String {
        String(Int((end.timeIntervalSince(start) * 1000).rounded()))
    }
}
