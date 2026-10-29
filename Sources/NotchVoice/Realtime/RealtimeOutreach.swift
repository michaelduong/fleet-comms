//  RealtimeOutreach.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation

/// Holds the initial reading until its transcript proves the provider kept the supplied words.
@MainActor
final class RealtimeOutreach {
    let reply: SessionReplyReader.Reply
    let spokenText: String
    let readingText: String
    var completed = false
    private var pcm = Data()
    private(set) var transcript = ""

    init(reply: SessionReplyReader.Reply, spokenText: String? = nil) {
        self.reply = reply
        self.spokenText = spokenText ?? reply.text
        readingText = OutreachWire.readingText(self.spokenText)
    }

    func consume(_ event: RealtimeWire.Event) throws -> [Float]? {
        switch event {
        case let .audioDelta(_, data):
            guard pcm.count + data.count <= 5_760_000 else { throw RealtimeError.readingFailed }
            pcm.append(data)
        case let .transcriptDelta(delta):
            guard transcript.utf8.count + delta.utf8.count <= 256_000 else { throw RealtimeError.readingFailed }
            transcript += delta
        case let .responseDone(status):
            return try checkedAudio(status: status)
        case let .error(code):
            EventLog.record("outreach_provider_error", ["code": code])
            throw RealtimeError.readingFailed
        case .functionCall: throw RealtimeError.readingFailed
        default: break
        }
        return nil
    }

    private func checkedAudio(status: String) throws -> [Float] {
        EventLog.record("outreach_reading_checked", [
            "status": status, "words_match": String(OutreachWire.matches(transcript, text: readingText)),
            "audio_bytes": String(pcm.count), "transcript_characters": String(transcript.count)
        ])
        guard status == "completed" else { throw RealtimeError.readingFailed }
        guard OutreachWire.matches(transcript, text: readingText) else { throw RealtimeError.readingMismatch }
        let samples = RealtimePCM.decode(pcm)
        pcm.removeAll()
        guard samples.contains(where: { abs($0) > 0.001 }) else { throw RealtimeError.readingFailed }
        return samples
    }
}
