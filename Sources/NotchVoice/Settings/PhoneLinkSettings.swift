//  PhoneLinkSettings.swift
//  NotchVoice
//
//  Created by Michael Duong on 11/17/26.

import Foundation
import Observation

/// The phone link's switch and its paired phones.
@MainActor
@Observable
final class PhoneLinkSettings {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored var onChange: (() -> Void)?

    /// Off by default: nothing listens for a phone until the owner turns this on.
    var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: AppSettings.Key.phoneLinkEnabled)
            onChange?()
        }
    }

    let pairings: PhonePairings

    init(defaults: UserDefaults, onChange: (() -> Void)? = nil) {
        self.defaults = defaults
        self.onChange = onChange
        pairings = PhonePairings(defaults: defaults)
        enabled = defaults.bool(forKey: AppSettings.Key.phoneLinkEnabled)
        // The lasting pairing code is gone: phones pair by QR and each gets its own key.
        defaults.removeObject(forKey: AppSettings.Key.phoneToken)
    }
}
