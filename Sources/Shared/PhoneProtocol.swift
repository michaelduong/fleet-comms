//  PhoneProtocol.swift
//  NotchVoice
//
//  Created by Michael Duong on 11/17/26.

import Foundation

/// The wire format between the Mac (base station) and the iPhone handset, over one WebSocket.
/// Text frames carry a `PhoneMessage` as JSON. Binary frames carry raw little-endian Float32 mono samples:
/// 16 kHz from the phone's microphone, 24 kHz of rendered reply speech (radio effect included) from the Mac.
struct PhoneMessage: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        /// Phone to Mac: first frame, carries the pairing token.
        case hello
        /// Phone to Mac: begin an utterance; microphone frames follow.
        case start
        /// Phone to Mac: the owner let go; send what was said now.
        case release
        /// Phone to Mac: drop the utterance.
        case cancel
        /// Phone to Mac: stop the reply that is playing.
        case stopSpeech
        /// Mac to phone: the token was accepted.
        case ready
        /// Mac to phone: the pill's state, with a message when it has one.
        case state
        /// Mac to phone: the live words of the utterance.
        case transcript
        /// Mac to phone: a reply begins; `text` is what is spoken.
        case speech
        /// Mac to phone: the next binary frames belong to `text[start ..< start + length]` (UTF-16).
        case part
        /// Mac to phone: nothing more follows this reply.
        case speechEnd
    }

    var kind: Kind
    var token: String?
    var text: String?
    var state: String?
    var start: Int?
    var length: Int?
    var assistant: Bool?

    init(_ kind: Kind) {
        self.kind = kind
    }

    private enum CodingKeys: String, CodingKey {
        case kind = "t", token, text, state, start, length, assistant
    }
}

enum PhoneLink {
    static let port: UInt16 = 47653
    static let micRate = 16000.0
    static let speechRate = 24000.0
    /// Release after this long counts as hold-to-talk; shorter is a tap, and the pause ends the turn.
    static let holdSeconds = 0.5

    static func data(_ samples: [Float]) -> Data {
        samples.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    static func samples(_ data: Data) -> [Float] {
        let count = data.count / MemoryLayout<Float>.size
        return [Float](unsafeUninitializedCapacity: count) { buffer, initialized in
            _ = data.copyBytes(to: UnsafeMutableRawBufferPointer(buffer))
            initialized = count
        }
    }
}
