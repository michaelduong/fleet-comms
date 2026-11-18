//  PhonePairings.swift
//  NotchVoice
//
//  Created by Michael Duong on 11/17/26.

import Foundation
import Observation

/// The phones paired with this Mac, and the one-time code that adds the next one.
/// Keys live in the Keychain; the list a person sees (name, date) is not secret and lives in defaults.
@MainActor
@Observable
final class PhonePairings {
    struct Phone: Codable, Identifiable, Equatable {
        let id: String
        var name: String
        var pairedAt: Date
    }

    /// A code works for one scan until `expires`; it is never written to disk.
    struct Code: Equatable {
        let id: String
        let key: Data
        let expires: Date
    }

    static let codeLife: TimeInterval = 5 * 60

    private(set) var phones: [Phone]
    private(set) var code: Code?
    /// A phone claimed the code, so a window showing it can say so.
    private(set) var lastPaired: Phone?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let keys: any PhoneKeyStore
    @ObservationIgnored private var expiry: Task<Void, Never>?
    /// The credentials the listener accepts changed.
    @ObservationIgnored var onKeysChanged: (() -> Void)?
    @ObservationIgnored var onRemoved: ((String) -> Void)?

    private static let listKey = "phonePairedList"
    private static let pairingPrefix = "pair-"

    init(defaults: UserDefaults, keys: any PhoneKeyStore = KeychainKeyStore(service: "fleetcomms.phone-keys")) {
        self.defaults = defaults
        self.keys = keys
        phones = defaults.data(forKey: Self.listKey).flatMap { try? JSONDecoder().decode([Phone].self, from: $0) } ?? []
    }

    /// Every pre-shared key the listener should accept right now.
    var credentials: [PhoneTLS.Credential] {
        var list = phones.compactMap { phone in
            keys.load(id: phone.id).map { PhoneTLS.Credential(identity: phone.id, key: $0) }
        }
        if let code, code.expires > Date() {
            list.append(PhoneTLS.Credential(identity: Self.pairingPrefix + code.id, key: code.key))
        }
        return list
    }

    func hasPhone(_ id: String) -> Bool {
        phones.contains { $0.id == id }
    }

    @discardableResult
    func beginPairing(now: Date = Date()) -> Code {
        let id = Self.randomHex(4)
        let key = Data((0 ..< 16).map { _ in UInt8.random(in: .min ... .max) })
        let code = Code(id: id, key: key, expires: now.addingTimeInterval(Self.codeLife))
        self.code = code
        lastPaired = nil
        onKeysChanged?()
        expiry?.cancel()
        expiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.codeLife))
            guard !Task.isCancelled else { return }
            self?.cancelPairing()
        }
        return code
    }

    func cancelPairing() {
        guard code != nil else { return }
        code = nil
        expiry?.cancel()
        onKeysChanged?()
    }

    /// Spends the code for a new phone: nil when the id is wrong, spent or past its time.
    func claim(codeID: String, now: Date = Date()) -> (phone: Phone, key: Data)? {
        guard let code, code.id == codeID, code.expires > now else { return nil }
        let phone = Phone(id: UUID().uuidString, name: "iPhone", pairedAt: now)
        let key = Data((0 ..< 32).map { _ in UInt8.random(in: .min ... .max) })
        keys.save(key, for: phone.id)
        phones.append(phone)
        save()
        lastPaired = phone
        self.code = nil
        expiry?.cancel()
        onKeysChanged?()
        return (phone, key)
    }

    func remove(_ id: String) {
        keys.delete(id: id)
        phones.removeAll { $0.id == id }
        save()
        onRemoved?(id)
        onKeysChanged?()
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(phones), forKey: Self.listKey)
    }

    private static func randomHex(_ bytes: Int) -> String {
        (0 ..< bytes).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max)) }.joined()
    }
}
