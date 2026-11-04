//  RadioSettings.swift
//  NotchVoice
//
//  Created by Michael Duong on 11/4/26.

import Foundation
import Observation

@MainActor
@Observable
final class RadioSettings {
    @ObservationIgnored private let defaults: UserDefaults

    var enabled: Bool {
        didSet { defaults.set(enabled, forKey: "radioEnabled") }
    }

    var staticLevel: Double {
        didSet { defaults.set(staticLevel, forKey: "radioStaticLevel") }
    }

    var style: RadioStyle {
        didSet { defaults.set(style.rawValue, forKey: "radioStyle") }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        enabled = defaults.bool(forKey: "radioEnabled")
        staticLevel = min(100, max(0, AppSettings.double(defaults, "radioStaticLevel") ?? 25))
        style = defaults.string(forKey: "radioStyle").flatMap(RadioStyle.init) ?? .policeDispatch
    }
}
