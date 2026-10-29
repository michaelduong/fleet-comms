//  UpdateConfigurationTests.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation
@testable import NotchVoice
import Testing

struct UpdateConfigurationTests {
    private func info(enabled: String = "YES", key: String, feed: String? = nil) -> [String: Any] {
        [
            "FleetCommsUpdatesEnabled": enabled,
            "SUPublicEDKey": key,
            "SUFeedURL": feed ?? UpdateConfiguration.feedURL.absoluteString
        ]
    }

    @Test func placeholderAndMissingConfigurationNeverStart() {
        #expect(!UpdateConfiguration(info: [:]).isReady)
        #expect(!UpdateConfiguration(info: info(key: "REPLACE_WITH_SPARKLE_PUBLIC_ED25519_KEY")).isReady)
        #expect(!UpdateConfiguration().isReady)
    }

    @Test func activationRequiresKeyAndExpectedHTTPSFeed() {
        // Synthetic bytes exercise validation only; no signing key is generated.
        let key = Data(repeating: 1, count: 32).base64EncodedString()
        #expect(UpdateConfiguration(info: info(key: key)).isReady)
        #expect(!UpdateConfiguration(info: info(enabled: "NO", key: key)).isReady)
        #expect(!UpdateConfiguration(info: info(key: key, feed: "http://example.com/appcast.xml")).isReady)
        #expect(!UpdateConfiguration(info: info(key: key, feed: "https://example.com/appcast.xml")).isReady)
        for count in [0, 31, 33] {
            #expect(!UpdateConfiguration(info: info(key: Data(repeating: 1, count: count).base64EncodedString()))
                .isReady)
        }
        #expect(!UpdateConfiguration(info: info(key: Data(repeating: 0, count: 32).base64EncodedString())).isReady)
    }
}
