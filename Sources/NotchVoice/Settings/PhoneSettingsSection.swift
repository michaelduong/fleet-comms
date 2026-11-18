//  PhoneSettingsSection.swift
//  NotchVoice
//
//  Created by Michael Duong on 11/17/26.

import SwiftUI

/// Turns the phone link on and shows what the handset needs to pair.
struct PhoneSettingsSection: View {
    @Bindable var settings: AppSettings
    @State private var showingPair = false

    var body: some View {
        Section("Phone link") {
            Toggle("Allow the iPhone handset", isOn: $settings.phone.enabled)
                .accessibilityIdentifier("settings.advanced.phoneLink")
            if settings.phone.enabled {
                ForEach(settings.phone.pairings.phones) { phone in
                    LabeledContent(phone.name, value: phone.pairedAt.formatted(date: .abbreviated, time: .omitted))
                        .accessibilityIdentifier("settings.advanced.phone.\(phone.id)")
                    Button("Remove \(phone.name)", role: .destructive) { settings.phone.pairings.remove(phone.id) }
                        .accessibilityIdentifier("settings.advanced.phoneRemove.\(phone.id)")
                }
                Button("Pair iPhone…") { showingPair = true }
                    .accessibilityIdentifier("settings.advanced.phonePair")
            }
            SettingsNote(
                text: "Lets the Fleet Comms handset on your iPhone talk through this Mac, over Tailscale or your "
                    + "home network. Pair iPhone shows a code that works once, for five minutes: scan it in the "
                    + "handset. The link is encrypted with a key only that phone holds. While it is connected, "
                    + "replies play on the phone, not on this Mac. Remove a phone to cut it off.",
                identifier: "settings.advanced.phoneNote"
            )
        }
        .sheet(isPresented: $showingPair) { PhonePairSheet(pairings: settings.phone.pairings) }
    }
}
