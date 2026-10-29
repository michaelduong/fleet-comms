//  AssistantWire.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation

/// The slice of the `claude --print` stream-json protocol this app writes and reads.
enum AssistantWire {
    enum Event: Equatable {
        /// Any streamed model output; the first one marks first-token latency.
        case delta
        case reply(AssistantReply)
        case failed(String)
        case other
    }

    static func userLine(_ text: String) throws -> Data {
        let message: [String: Any] = ["type": "user", "message": ["role": "user", "content": text]]
        var data = try JSONSerialization.data(withJSONObject: message)
        data.append(0x0A)
        return data
    }

    static func parse(_ line: String) -> Event {
        guard let parsed = try? JSONDecoder().decode(WireLine.self, from: Data(line.utf8)) else { return .other }
        switch parsed.type {
        case "stream_event":
            return parsed.event?.type == "content_block_delta" ? .delta : .other
        case "result":
            if parsed.isError == false {
                guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      let structured = object["structured_output"],
                      let data = try? JSONSerialization.data(withJSONObject: structured),
                      let reply = try? MessengerCommand.validated(data) else { return .failed("malformed") }
                return .reply(reply)
            }
            return .failed(parsed.subtype ?? "error")
        default:
            return .other
        }
    }
}

/// One stdout line of `claude --print --output-format stream-json`.
private struct WireLine: Decodable {
    struct StreamEvent: Decodable {
        let type: String
    }

    let type: String
    let subtype: String?
    let isError: Bool?
    let event: StreamEvent?

    enum CodingKeys: String, CodingKey {
        case type, subtype, event
        case isError = "is_error"
    }
}
