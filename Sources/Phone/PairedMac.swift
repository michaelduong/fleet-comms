//  PairedMac.swift
//  FleetCommsPhone
//
//  Created by Michael Duong on 11/17/26.

import Foundation

/// The Mac this phone paired with: where to reach it, the name the Mac gave this phone, and the link key
/// (in the Keychain, never in defaults).
struct PairedMac {
    var name = "your Mac"
    var hosts: [String] = []
    var phoneID = ""

    private static let keys: any PhoneKeyStore = KeychainKeyStore(service: "fleetcomms.link-key")
    private static let keyID = "mac"

    init(defaults: UserDefaults) {
        hosts = defaults.stringArray(forKey: "hosts") ?? []
        name = defaults.string(forKey: "macName") ?? name
        phoneID = defaults.string(forKey: "phoneID") ?? ""
        // The lasting host and code from before QR pairing are no longer used.
        for old in ["host", "token"] {
            defaults.removeObject(forKey: old)
        }
    }

    var key: Data? {
        Self.keys.load(id: Self.keyID)
    }

    var isPaired: Bool {
        !hosts.isEmpty && !phoneID.isEmpty && key != nil
    }

    var credential: PhoneTLS.Credential? {
        key.map { PhoneTLS.Credential(identity: phoneID, key: $0) }
    }

    /// Keeps what the Mac handed over when the one-time code was accepted.
    mutating func save(link: PhonePairingLink, phoneID: String, key: Data, defaults: UserDefaults) {
        Self.keys.save(key, for: Self.keyID)
        self.phoneID = phoneID
        hosts = link.hosts
        name = link.name
        defaults.set(phoneID, forKey: "phoneID")
        defaults.set(hosts, forKey: "hosts")
        defaults.set(name, forKey: "macName")
    }
}
