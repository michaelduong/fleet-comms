//  PhoneTLS.swift
//  NotchVoice
//
//  Created by Michael Duong on 11/17/26.

import Foundation
import Network
import Security

/// TLS 1.2 with a pre-shared key: the phone and Mac encrypt the link with a secret only the two hold,
/// so no certificate is needed and Wi-Fi sniffing sees nothing.
enum PhoneTLS {
    struct Credential: Sendable {
        var identity: String
        var key: Data
    }

    static func options(_ credentials: [Credential]) -> NWProtocolTLS.Options {
        let options = NWProtocolTLS.Options()
        let sec = options.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(sec, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(sec, .TLSv12)
        if let suite = tls_ciphersuite_t(rawValue: UInt16(TLS_ECDHE_PSK_WITH_CHACHA20_POLY1305_SHA256)) {
            sec_protocol_options_append_tls_ciphersuite(sec, suite)
        }
        for credential in credentials {
            let key = credential.key.withUnsafeBytes { DispatchData(bytes: $0) } as __DispatchData
            let identity = Data(credential.identity.utf8).withUnsafeBytes { DispatchData(bytes: $0) } as __DispatchData
            sec_protocol_options_add_pre_shared_key(sec, key, identity)
        }
        return options
    }

    /// TCP, then TLS, then WebSocket, the order Network stacks them.
    static func parameters(_ credentials: [Credential]) -> NWParameters {
        let parameters = NWParameters(tls: options(credentials), tcp: NWProtocolTCP.Options())
        parameters.defaultProtocolStack.applicationProtocols.insert(NWProtocolWebSocket.Options(), at: 0)
        return parameters
    }
}
