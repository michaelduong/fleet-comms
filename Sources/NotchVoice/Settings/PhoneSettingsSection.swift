//  PhoneSettingsSection.swift
//  NotchVoice
//
//  Created by Michael Duong on 11/17/26.

import SwiftUI

/// Turns the phone link on and shows what the handset needs to pair.
struct PhoneSettingsSection: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Section("Phone link") {
            Toggle("Allow the iPhone handset", isOn: $settings.phone.enabled)
                .accessibilityIdentifier("settings.advanced.phoneLink")
            if settings.phone.enabled {
                LabeledContent("Host", value: ProcessInfo.processInfo.hostName)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("settings.advanced.phoneHost")
                LabeledContent("Port", value: String(PhoneLink.port))
                    .accessibilityIdentifier("settings.advanced.phonePort")
                LabeledContent("Pairing code", value: settings.phone.token)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("settings.advanced.phoneCode")
                Button("New Pairing Code", action: settings.phone.regenerateToken)
                    .accessibilityIdentifier("settings.advanced.phoneNewCode")
            }
            SettingsNote(
                text: "Lets the Fleet Comms handset on your iPhone talk through this Mac, over Tailscale or your "
                    + "home network. Enter the host (or this Mac's Tailscale name or address) and the pairing code "
                    + "in the handset. While it is connected, replies play on the phone, not on this Mac. "
                    + "A new code unpairs every phone.",
                identifier: "settings.advanced.phoneNote"
            )
        }
    }
}
