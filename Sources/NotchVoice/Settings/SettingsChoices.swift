//  SettingsChoices.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation

enum SpeechModelChoice: String, CaseIterable, Identifiable, Sendable {
    case fluidSpeechPro
    case parakeetRealtime320
    case parakeetRealtime160
    case parakeetTdtV2

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .parakeetRealtime320: "Parakeet Realtime (end-of-utterance, 320 ms)"
        case .parakeetRealtime160: "Parakeet Realtime (end-of-utterance, 160 ms)"
        case .parakeetTdtV2: "Parakeet TDT v2 (English)"
        case .fluidSpeechPro: "Fluid Speech Pro (English)"
        }
    }

    /// Fluid Speech Pro when FluidVoice has installed it, else the realtime model.
    static var preferred: SpeechModelChoice {
        FluidSpeechPro.isInstalled ? .fluidSpeechPro : .parakeetRealtime320
    }
}

/// Who answers out loud: the on-device fast lane, or a speech-to-speech model on a subscription login.
enum VoiceLane: String, CaseIterable, Identifiable, Sendable {
    case onDevice
    case chatGPTRealtime
    case grokVoice

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .onDevice: "On-device"
        case .chatGPTRealtime: "ChatGPT Realtime"
        case .grokVoice: "Grok Voice"
        }
    }

    var provider: RealtimeProvider? {
        switch self {
        case .onDevice: nil
        case .chatGPTRealtime: .chatGPT
        case .grokVoice: .grok
        }
    }
}

/// What decides that the owner has finished speaking.
enum EndOfTurnChoice: String, CaseIterable, Identifiable, Sendable {
    case silence
    /// Smart Turn judges each pause from the voice; the silence threshold still ends the turn if it waits.
    case smartTurn

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .silence: "Silence"
        case .smartTurn: "Smart Turn"
        }
    }
}

struct VoiceChoice: Identifiable, Hashable, Sendable {
    let id: String
    let title: String

    static let defaultID = "af_heart"

    static let all: [VoiceChoice] = [
        VoiceChoice(id: "af_heart", title: "Heart (US, female)"),
        VoiceChoice(id: "af_bella", title: "Bella (US, female)"),
        VoiceChoice(id: "af_nicole", title: "Nicole (US, female)"),
        VoiceChoice(id: "am_adam", title: "Adam (US, male)"),
        VoiceChoice(id: "am_michael", title: "Michael (US, male)"),
        VoiceChoice(id: "am_echo", title: "Echo (US, male)"),
        VoiceChoice(id: "am_eric", title: "Eric (US, male)"),
        VoiceChoice(id: "am_fenrir", title: "Fenrir (US, male)"),
        VoiceChoice(id: "am_liam", title: "Liam (US, male)"),
        VoiceChoice(id: "am_onyx", title: "Onyx (US, male)"),
        VoiceChoice(id: "am_puck", title: "Puck (US, male)"),
        VoiceChoice(id: "am_santa", title: "Santa (US, male, novelty)"),
        VoiceChoice(id: "bf_emma", title: "Emma (UK, female)"),
        VoiceChoice(id: "bm_george", title: "George (UK, male)"),
        VoiceChoice(id: "bm_lewis", title: "Lewis (UK, male)"),
        VoiceChoice(id: "bm_daniel", title: "Daniel (UK, male)"),
        VoiceChoice(id: "bm_fable", title: "Fable (UK, male)")
    ]
}

enum TextSizeChoice: String, CaseIterable, Identifiable, Sendable {
    case standard
    case large
    case extraLarge
    case largest

    var id: String {
        rawValue
    }

    var scale: CGFloat {
        switch self {
        case .standard: 1.0
        case .large: 1.25
        case .extraLarge: 1.5
        case .largest: 2.0
        }
    }

    var title: String {
        switch self {
        case .standard: "Standard"
        case .large: "Large"
        case .extraLarge: "Extra Large"
        case .largest: "Largest"
        }
    }
}

/// Where the pill lives on screen.
enum PillPlacement: String, CaseIterable, Identifiable, Sendable {
    case notch
    case bottomCenter
    case sideDock

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .notch: "Notch"
        case .bottomCenter: "Bottom center"
        case .sideDock: "Side dock"
        }
    }

    /// The notch is fixed to one screen; the other placements float on the screen in use.
    var isFloating: Bool {
        self != .notch
    }
}

enum SettingsOptions {
    static let silenceSeconds: [Double] = [0.5, 0.8, 1.0, 1.5, 2.0, 2.5, 3.0]
    static let replyTimeoutSeconds: [Double] = [30, 60, 120, 300]
    /// 0 keeps a reply on screen until dismissed.
    static let autoDismissSeconds: [Double] = [0, 3, 5, 10, 20]
    static let hangUpAfterQuietSeconds: [Double] = [5, 10, 20, 30]
}

enum SpeechSpeed: Float, CaseIterable, Sendable {
    case normal = 1.0
    case brisk = 1.25
    case fast = 1.5
    case faster = 1.75
    case double = 2.0

    var title: String {
        switch self {
        case .normal: "1.0x"
        case .brisk: "1.25x"
        case .fast: "1.5x"
        case .faster: "1.75x"
        case .double: "2.0x"
        }
    }
}
