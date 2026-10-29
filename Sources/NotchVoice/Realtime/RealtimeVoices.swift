//  RealtimeVoices.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation

/// The voices each realtime lane offers. OpenAI's list is every voice its realtime socket
/// accepted on this login (10/28/26); OpenAI publishes no genders, so those hints are by ear.
/// xAI's list and genders come from its `GET /v1/tts/voices`, the roster speech-to-speech shares.
extension RealtimeProvider {
    var voices: [VoiceChoice] {
        self == .grok ? Self.grokVoices : Self.chatGPTVoices
    }

    var defaultVoice: String {
        self == .grok ? "rex" : "cedar"
    }

    private static let chatGPTVoices = voices([
        ("alloy", "neutral"), ("ash", "male"), ("ballad", "male"), ("cedar", "male"), ("coral", "female"),
        ("echo", "male"), ("marin", "female"), ("sage", "female"), ("shimmer", "female"), ("verse", "male")
    ])

    private static let grokVoices = voices([
        ("altair", "male"), ("ara", "female"), ("atlas", "male"), ("aurora", "female"), ("carina", "female"),
        ("castor", "male"), ("celeste", "female"), ("cosmo", "male"), ("eve", "female"), ("helios", "male"),
        ("helix", "male"), ("iris", "female"), ("kepler", "male"), ("leo", "male"), ("liora", "female"),
        ("lumen", "male"), ("luna", "female"), ("lux", "male"), ("naksh", "male"), ("orion", "male"),
        ("perseus", "male"), ("rex", "male"), ("rigel", "male"), ("sal", "male"), ("sirius", "male"),
        ("ursa", "female"), ("zagan", "male"), ("zenith", "male")
    ])

    private static func voices(_ list: [(String, String)]) -> [VoiceChoice] {
        list.map { VoiceChoice(id: $0.0, title: "\($0.0.capitalized) (\($0.1))") }
    }
}
