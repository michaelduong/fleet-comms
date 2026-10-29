//  RealtimeWire.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation

/// The slice of the Realtime GA protocol this app sends and reads. OpenAI and xAI share it.
enum RealtimeWire {
    static let sampleRate = 24000

    enum Event: Equatable {
        case sessionCreated
        case speechStarted
        case speechStopped
        case userTranscript(String)
        case responseCreated
        case audioDelta(itemID: String, audio: Data)
        case transcriptDelta(String)
        case functionCall(callID: String, name: String, arguments: String)
        case responseDone(status: String)
        case error(code: String)
        case other
    }

    struct Session {
        let provider: RealtimeProvider
        let voice: String
        let instructions: String
        let silenceMs: Int
    }

    static func sessionUpdate(_ session: Session) -> String {
        let format: [String: Any] = ["type": "audio/pcm", "rate": sampleRate]
        var input: [String: Any] = [
            "format": format,
            "turn_detection": [
                "type": "server_vad", "silence_duration_ms": session.silenceMs,
                "create_response": true, "interrupt_response": true
            ],
            "transcription": ["model": session.provider.transcriptionModel]
        ]
        if session.provider == .chatGPT {
            input["noise_reduction"] = ["type": "near_field"]
        }
        let body: [String: Any] = [
            "type": "realtime",
            "instructions": session.instructions,
            "output_modalities": ["audio"],
            "audio": ["input": input, "output": ["format": format, "voice": session.voice]],
            "tools": [RealtimePrompt.handoffTool, RealtimePrompt.lookupTool],
            "tool_choice": "auto"
        ]
        return encode(["type": "session.update", "session": body])
    }

    static func appendAudio(_ pcm16: Data) -> String {
        encode(["type": "input_audio_buffer.append", "audio": pcm16.base64EncodedString()])
    }

    static func toolResult(callID: String, output: String) -> String {
        encode([
            "type": "conversation.item.create",
            "item": ["type": "function_call_output", "call_id": callID, "output": output]
        ])
    }

    static func userText(_ text: String) -> String {
        encode([
            "type": "conversation.item.create",
            "item": ["type": "message", "role": "user", "content": [["type": "input_text", "text": text]]]
        ])
    }

    static func createResponse() -> String {
        encode(["type": "response.create"])
    }

    /// Tells the model how much of its answer was heard before the owner talked over it.
    static func truncate(itemID: String, playedMs: Int) -> String {
        encode([
            "type": "conversation.item.truncate", "item_id": itemID, "content_index": 0, "audio_end_ms": playedMs
        ])
    }

    /// Events that carry nothing this app reads.
    private static let bareEvents: [String: Event] = [
        "session.created": .sessionCreated,
        "input_audio_buffer.speech_started": .speechStarted,
        "input_audio_buffer.speech_stopped": .speechStopped,
        "response.created": .responseCreated
    ]

    static func parse(_ text: String) -> Event {
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let type = object["type"] as? String else { return .other }
        if let bare = bareEvents[type] {
            return bare
        }
        let string = { (key: String) in object[key] as? String ?? "" }
        switch type {
        case "conversation.item.input_audio_transcription.completed": return .userTranscript(string("transcript"))
        case "response.output_audio.delta":
            return .audioDelta(itemID: string("item_id"), audio: Data(base64Encoded: string("delta")) ?? Data())
        case "response.output_audio_transcript.delta": return .transcriptDelta(string("delta"))
        case "response.function_call_arguments.done":
            return .functionCall(callID: string("call_id"), name: string("name"), arguments: string("arguments"))
        case "response.done":
            return .responseDone(status: (object["response"] as? [String: Any])?["status"] as? String ?? "")
        case "error":
            let error = object["error"] as? [String: Any]
            return .error(code: error?["code"] as? String ?? error?["type"] as? String ?? "unknown")
        default: return .other
        }
    }

    private static func encode(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return "{}" }
        return String(bytes: data, encoding: .utf8) ?? "{}"
    }
}
