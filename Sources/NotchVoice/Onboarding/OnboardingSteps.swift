//  OnboardingSteps.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import AppKit
import SwiftUI

struct WelcomeStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                // Read from the asset catalog: a build run outside Launch Services shows a generic app icon.
                Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .accessibilityIdentifier("onboarding.welcome.icon")
                OnboardingHeading(
                    title: "Welcome to Fleet Comms",
                    subtitle: "Talk to Firstmate from the notch and hear the reply."
                )
                .padding(.bottom, -18)
            }
            point("waveform", "Press the hotkey, speak, pause. Your words become a note to Firstmate, "
                + "or a quick spoken answer from the fast assistant.")
            point("lock.shield", "Speech recognition, voice detection and the voice stay on this Mac. "
                + "The fast assistant runs through your own Claude Code login.")
            point("antenna.radiowaves.left.and.right", "Two optional realtime lanes (ChatGPT, Grok) send your voice "
                + "to OpenAI or xAI. They are off until you turn them on in Settings › Realtime.")
        }
        .accessibilityIdentifier("onboarding.welcome")
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(Color.accentColor)
        }
    }
}

struct MicrophoneStep: View {
    let permission: MicrophonePermission

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            OnboardingHeading(
                title: "Microphone",
                subtitle: "The microphone is on only while the pill is listening: after the hotkey, and briefly "
                    + "after a spoken reply when follow-up listening is on."
            )
            switch permission.state {
            case .granted:
                StatusText(tone: .ready, text: "Microphone access is allowed.", identifier: "onboarding.mic.status")
            case .notDetermined:
                StatusText(tone: .warning, text: "Not asked yet.", identifier: "onboarding.mic.status")
                Button("Allow Microphone") { permission.request() }
                    .accessibilityIdentifier("onboarding.mic.allow")
            case .denied:
                StatusText(
                    tone: .missing, text: "Access is off. Allow Fleet Comms under Privacy & Security › Microphone.",
                    identifier: "onboarding.mic.status"
                )
                Button("Open System Settings") { MicrophonePermission.openSystemSettings() }
                    .accessibilityIdentifier("onboarding.mic.openSettings")
            }
            SettingsNote(
                text: "No Accessibility access is needed: the hotkey is a system hot key, not a keyboard tap.",
                identifier: "onboarding.mic.note"
            )
        }
        .onAppear { permission.refresh() }
        .accessibilityIdentifier("onboarding.microphone")
    }
}

struct FirstMateStep: View {
    let settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            OnboardingHeading(
                title: "Firstmate",
                subtitle: "Point Fleet Comms at a firstmate home. Notes are filed with its fm-inbox.sh and "
                    + "replies are read back from the same place; nothing leaves this Mac."
            )
            Form {
                FirstmateHomeField(settings: settings)
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, -20)
        }
        .accessibilityIdentifier("onboarding.firstMate")
    }
}

struct ModelsStep: View {
    let library: ModelLibrary
    let settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            OnboardingHeading(
                title: "Local models",
                subtitle: "Three small downloads run everything on device: voice detection, the voice, and the "
                    + "default speech recognizer. Others can be added later in Settings › Models."
            )
            Form {
                ForEach(LocalModel.starterSet) { model in
                    ModelRow(model: model, library: library, inUse: true, compact: true) {}
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, -20)
            HStack {
                if library.starterSetInstalled {
                    StatusText(tone: .ready, text: "All three are installed.", identifier: "onboarding.models.status")
                } else {
                    Button("Download All (about \(ByteCount.string(starterBytes)))") { library.downloadStarterSet() }
                        .disabled(LocalModel.starterSet.contains { library.status($0).isDownloading })
                        .accessibilityIdentifier("onboarding.models.downloadAll")
                    Text("Skipped downloads happen on first use instead.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { library.refresh() }
        .accessibilityIdentifier("onboarding.models")
    }

    private var starterBytes: Int64 {
        LocalModel.starterSet.reduce(0) { $0 + $1.approximateBytes }
    }
}

struct DoneStep: View {
    let settings: AppSettings
    let openSettings: (SettingsSection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            OnboardingHeading(
                title: "Ready",
                subtitle: "Press \(settings.hotkey.title), or click the pill in the notch, and talk. Pause for "
                    + "about a second and it sends."
            )
            Label("Esc or the hotkey cancels while listening; the hotkey interrupts a reply.", systemImage: "escape")
            Label("The menu-bar icon switches the voice lane and the fast assistant.", systemImage: "menubar.rectangle")
            Label("Everything else lives in Settings.", systemImage: "gearshape")
            Button("Open Settings") { openSettings(.general) }
                .accessibilityIdentifier("onboarding.done.openSettings")
        }
        .accessibilityIdentifier("onboarding.done")
    }
}
