//  AppSettings+InitialValues.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation

extension AppSettings {
    static func initialOutreachHangUp(_ defaults: UserDefaults) -> Double {
        let value = double(defaults, Key.outreachHangUpSeconds) ?? 25
        return [10.0, 20, 25, 30].contains(value) ? value : 25
    }

    static func initialRealtimeVoices(_ defaults: UserDefaults) -> [String: String] {
        [RealtimeProvider.chatGPT, .grok].reduce(into: [:]) { voices, provider in
            voices[provider.id] = defaults.string(forKey: Key.realtimeVoicePrefix + provider.id)
        }
    }

    /// `double(forKey:)` also reads a launch-argument override, which arrives as a string.
    static func double(_ defaults: UserDefaults, _ key: String) -> Double? {
        defaults.object(forKey: key) == nil ? nil : defaults.double(forKey: key)
    }
}
