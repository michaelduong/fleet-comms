//  RealtimeSettingsView.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import SwiftUI

/// The opt-in speech-to-speech lanes, each on a vendor CLI's own login.
struct RealtimeSettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section("Voice lane") {
                Picker("Who answers out loud", selection: $settings.voiceLane) {
                    ForEach(availableLanes) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup)
                .accessibilityIdentifier("settings.realtime.lane")
                SettingsNote(
                    text: "On-device keeps everything on this Mac. A realtime lane opens a hands-free call with the "
                        + "model instead; it still hands real work to Firstmate.",
                    identifier: "settings.realtime.laneNote"
                )
                Picker("Hang up after quiet", selection: $settings.hangUpAfterQuietSeconds) {
                    ForEach(SettingsOptions.hangUpAfterQuietSeconds, id: \.self) { Text("\(Int($0)) s").tag($0) }
                }
                .accessibilityIdentifier("settings.realtime.hangUp")
            }
            OutreachSettingsView(settings: settings)
            providerSection(.chatGPT, cli: "Codex CLI")
            providerSection(.grok, cli: "Grok CLI")
            Section("Privacy") {
                SettingsNote(
                    text: "Realtime lanes stream your voice to OpenAI or xAI for the length of the call. They reuse "
                        + "the login the Codex or Grok CLI saved on this Mac, which neither vendor documents as "
                        + "supported; the token only mints a short-lived session key and is never written or logged.",
                    identifier: "settings.realtime.privacy"
                )
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("settings.realtime")
    }

    /// A lane without a login cannot be chosen; its section says how to get one.
    private var availableLanes: [VoiceLane] {
        VoiceLane.allCases.filter { lane in
            guard let provider = lane.provider else { return true }
            return settings.isRealtimeEnabled(provider)
                && (SubscriptionLogin.status(provider) != .missing || settings.voiceLane == lane)
        }
    }

    private func providerSection(_ provider: RealtimeProvider, cli: String) -> some View {
        Section(provider.title) {
            Toggle("Enable \(provider.title)", isOn: Binding(
                get: { settings.isRealtimeEnabled(provider) },
                set: { settings.setRealtimeEnabled($0, for: provider) }
            ))
            .accessibilityIdentifier("settings.realtime.enabled.\(provider.id)")
            SettingsNote(
                text: "Uses your own \(provider == .chatGPT ? "ChatGPT" : "SuperGrok") subscription.",
                identifier: "settings.realtime.subscription.\(provider.id)"
            )
            loginStatus(provider, cli: cli)
            Picker("Voice", selection: Binding(
                get: { settings.realtimeVoice(provider) },
                set: { settings.setRealtimeVoice($0, for: provider) }
            )) {
                ForEach(provider.voices) { Text($0.title).tag($0.id) }
            }
            .accessibilityIdentifier("settings.realtime.voice.\(provider.id)")
            SettingsNote(
                text: "Model \(provider.model). A new voice applies from the next call.",
                identifier: "settings.realtime.model.\(provider.id)"
            )
        }
    }

    @ViewBuilder
    private func loginStatus(_ provider: RealtimeProvider, cli: String) -> some View {
        switch SubscriptionLogin.status(provider) {
        case .valid:
            StatusText(
                tone: .ready, text: "Signed in through the \(cli).",
                identifier: "settings.realtime.login.\(provider.id)"
            )
        case .expired where provider == .grok:
            StatusText(
                tone: .ready, text: "Signed in through the \(cli); the token is renewed when a call starts.",
                identifier: "settings.realtime.login.\(provider.id)"
            )
        case .expired:
            StatusText(
                tone: .warning, text: "Sign-in expired. Run \(provider.loginCommand) in a terminal.",
                identifier: "settings.realtime.login.\(provider.id)"
            )
        case .missing:
            StatusText(
                tone: .neutral,
                text: "Not signed in. Install the \(cli) and run \(provider.loginCommand) before choosing this lane.",
                identifier: "settings.realtime.login.\(provider.id)"
            )
        }
    }
}
