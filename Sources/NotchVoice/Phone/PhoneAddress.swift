//  PhoneAddress.swift
//  NotchVoice
//
//  Created by Michael Duong on 11/17/26.

import Foundation

/// How a phone can find this Mac: its local host name, then its Tailscale address when there is one.
enum PhoneAddress {
    /// The Tailscale IPv4 address (100.64.0.0/10) on any interface, read without asking Tailscale.
    static func tailscaleIPv4() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let address = pointer.pointee.ifa_addr,
                  address.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            let raw = address
                .withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            guard raw >> 22 == 0x191 else { continue } // 100.64.0.0/10
            return "\(raw >> 24).\((raw >> 16) & 255).\((raw >> 8) & 255).\(raw & 255)"
        }
        return nil
    }

    static func hosts() -> [String] {
        order(tailscale: tailscaleIPv4(), name: ProcessInfo.processInfo.hostName)
    }

    /// The local name first: it works on the same network without Tailscale, while a Tailscale address can
    /// hang the connection (FLC-35).
    static func order(tailscale: String?, name: String) -> [String] {
        [name, tailscale].compactMap(\.self)
    }

    static func link(for code: PhonePairings.Code) -> PhonePairingLink {
        PhonePairingLink(
            name: Host.current().localizedName ?? ProcessInfo.processInfo.hostName,
            hosts: hosts(), port: PhoneLink.port, id: code.id, key: code.key
        )
    }
}
