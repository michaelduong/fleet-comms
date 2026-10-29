//  OutreachVoice.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

enum OutreachVoice: String, CaseIterable, Identifiable {
    case kokoro, grokVoice, gptRealtime

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .kokoro: "Kokoro"
        case .grokVoice: "Grok Voice"
        case .gptRealtime: "GPT Realtime"
        }
    }

    var provider: RealtimeProvider? {
        switch self {
        case .kokoro: nil
        case .grokVoice: .grok
        case .gptRealtime: .chatGPT
        }
    }
}
