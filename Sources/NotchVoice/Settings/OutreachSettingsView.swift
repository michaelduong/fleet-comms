//  OutreachSettingsView.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import SwiftUI

struct OutreachSettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Section("Unprompted outreach") {
            Picker("Outreach voice", selection: $settings.outreachVoice) {
                ForEach(OutreachVoice.allCases) { Text($0.title).tag($0) }
            }
            .accessibilityIdentifier("settings.realtime.outreachVoice")
            if let provider = settings.outreachVoice.provider {
                Picker("Outreach voice option", selection: Binding(
                    get: { settings.realtimeVoice(provider) },
                    set: { settings.setRealtimeVoice($0, for: provider) }
                )) {
                    ForEach(provider.voices) { Text($0.title).tag($0.id) }
                }
                .accessibilityIdentifier("settings.realtime.outreachVoiceOption")
            }
            Picker("Hang up outreach call after quiet", selection: $settings.outreachHangUpSeconds) {
                ForEach([10.0, 20, 25, 30], id: \.self) { Text("\(Int($0)) s").tag($0) }
            }
            .accessibilityIdentifier("settings.realtime.outreachHangUp")
            SettingsNote(
                text: "Only messages Firstmate sends on its own. Replies to your voice notes keep their current "
                    + "voice. Realtime reads the message, then opens the microphone for a two-way call with the usual "
                    + "tools. The call stays visible until you hang up or the quiet window ends. "
                    + "Uses the selected lane's existing login and voice option; needs microphone permission. "
                    + "If unavailable or slow, Kokoro reads it without opening a call.",
                identifier: "settings.realtime.outreachNote"
            )
        }
        .accessibilityIdentifier("settings.realtime.outreach")
    }
}
