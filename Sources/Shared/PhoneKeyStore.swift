//  PhoneKeyStore.swift
//  NotchVoice
//
//  Created by Michael Duong on 11/17/26.

import Foundation
import Security

/// Where a link key lives: the Mac keeps one per paired phone, the phone keeps the one for its Mac.
protocol PhoneKeyStore: Sendable {
    func save(_ key: Data, for id: String)
    func load(id: String) -> Data?
    func delete(id: String)
}

struct KeychainKeyStore: PhoneKeyStore {
    let service: String

    private func query(_ id: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id
        ]
    }

    func save(_ key: Data, for id: String) {
        delete(id: id)
        var item = query(id)
        item[kSecValueData as String] = key
        #if os(iOS)
            // The phone reconnects from a push while locked.
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        #endif
        SecItemAdd(item as CFDictionary, nil)
    }

    func load(id: String) -> Data? {
        var item = query(id)
        item[kSecReturnData as String] = true
        var result: AnyObject?
        return SecItemCopyMatching(item as CFDictionary, &result) == errSecSuccess ? result as? Data : nil
    }

    func delete(id: String) {
        SecItemDelete(query(id) as CFDictionary)
    }
}

/// A key store that forgets at exit, for tests.
final class MemoryKeyStore: PhoneKeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var keys: [String: Data] = [:]

    func save(_ key: Data, for id: String) {
        lock.withLock { keys[id] = key }
    }

    func load(id: String) -> Data? {
        lock.withLock { keys[id] }
    }

    func delete(id: String) {
        lock.withLock { keys[id] = nil }
    }
}
