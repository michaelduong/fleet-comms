//  RealtimeProvider.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation

/// A speech-to-speech service reached on the owner's subscription login, never an API key.
/// Both speak the OpenAI Realtime GA vocabulary over a WebSocket.
struct RealtimeProvider: Sendable, Equatable {
    let id: String
    let title: String
    let model: String
    let transcriptionModel: String
    let mintURL: URL
    let socketURL: URL
    /// Where the login lives and how to renew it, for messages and the menu.
    let loginCommand: String

    static let chatGPT = RealtimeProvider(
        id: "chatgpt",
        title: "ChatGPT Realtime",
        model: "gpt-realtime-2.1",
        transcriptionModel: "gpt-4o-mini-transcribe",
        mintURL: URL(string: "https://api.openai.com/v1/realtime/client_secrets")!,
        socketURL: URL(string: "wss://api.openai.com/v1/realtime?model=gpt-realtime-2.1")!,
        loginCommand: "codex login"
    )

    static let grok = RealtimeProvider(
        id: "grok",
        title: "Grok Voice",
        model: "grok-voice-latest",
        transcriptionModel: "grok-transcribe",
        mintURL: URL(string: "https://api.x.ai/v1/realtime/client_secrets")!,
        socketURL: URL(string: "wss://api.x.ai/v1/realtime?model=grok-voice-latest")!,
        loginCommand: "grok login"
    )

    /// The body that mints a short-lived client secret, so the long-lived login token is only
    /// ever sent to the provider's HTTPS endpoint, never over the socket.
    var mintBody: [String: Any] {
        id == Self.grok.id
            ? ["expires_after": ["seconds": 600]]
            : ["session": ["type": "realtime", "model": model]]
    }
}
