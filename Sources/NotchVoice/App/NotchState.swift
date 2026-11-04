//  NotchState.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation

enum NotchState: Equatable {
    case idle
    case preparing(activity: String, step: String, fraction: Double?)
    case listening
    case thinking
    case sending
    case waiting
    case stillWorking
    case reply(text: String, speaking: Bool, from: ReplySource)
    case message(String)
    case call(CallPhase)
    /// A Claude question waiting in the pill. `AppModel.displayState` derives it; `state` never holds it.
    case question

    var isExpanded: Bool {
        self != .idle
    }

    var compactStatusText: String? {
        switch self {
        case .thinking: "Thinking…"
        case .sending: "Sending to Firstmate…"
        case .waiting: "Sent. Waiting for the reply…"
        default: nil
        }
    }

    /// Escape is taken from other apps only while listening, in a call or showing a reply.
    var claimsEscape: Bool {
        switch self {
        case .listening, .call, .reply: true
        default: false
        }
    }

    var isCall: Bool {
        if case .call = self {
            return true
        }
        return false
    }
}

/// Where a realtime call is: opening, hearing the owner, or the model talking.
enum CallPhase: Equatable {
    case connecting
    case listening
    case speaking
}

enum ReplySource: Equatable {
    case firstMate
    case assistant

    var title: String {
        switch self {
        case .firstMate: "Firstmate"
        case .assistant: "Assistant"
        }
    }
}
