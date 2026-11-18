//  PhoneLinkSettings.swift
//  NotchVoice
//
//  Created by Michael Duong on 11/17/26.

import Foundation
import Observation

/// The phone link's switch and pairing code.
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

    /// The pairing code the phone sends; changing it unpairs every phone.
    private(set) var token: String

    init(defaults: UserDefaults, onChange: (() -> Void)? = nil) {
        self.defaults = defaults
        self.onChange = onChange
        enabled = defaults.bool(forKey: AppSettings.Key.phoneLinkEnabled)
        token = defaults.string(forKey: AppSettings.Key.phoneToken) ?? Self.newToken()
        defaults.set(token, forKey: AppSettings.Key.phoneToken)
    }

    func regenerateToken() {
        token = Self.newToken()
        defaults.set(token, forKey: AppSettings.Key.phoneToken)
        onChange?()
    }

    private static func newToken() -> String {
        (0 ..< 4).map { _ in String(format: "%08x", UInt32.random(in: .min ... .max)) }.joined()
    }
}
