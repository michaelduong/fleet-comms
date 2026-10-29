//  GeneralSettingsView.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var settings: AppSettings
    let launchAtLogin: LaunchAtLogin
    var homeCandidates: [String]?

    var body: some View {
        Form {
            Section("Firstmate") {
                FirstmateHomeField(settings: settings, candidates: homeCandidates)
            }
            Section("Talking") {
                Picker("Hotkey", selection: $settings.hotkey) {
                    ForEach(HotkeyPreset.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("settings.general.hotkey")
                Picker("Placement", selection: $settings.pillPlacement) {
                    ForEach(PillPlacement.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("settings.general.placement")
                SettingsNote(
                    text: "Notch hangs the pill from the camera housing (a strip at the top centre of a Mac "
                        + "without one). Bottom center and Side dock float on the screen under the pointer.",
                    identifier: "settings.general.placementNote"
                )
                Picker("Card theme", selection: $settings.cardTheme) {
                    ForEach(CardTheme.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("settings.general.cardTheme")
                Picker("Text size", selection: $settings.textSize) {
                    ForEach(TextSizeChoice.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("settings.general.textSize")
            }
            Section("Replies") {
                Toggle("Speak Firstmate replies", isOn: $settings.speakFirstmateReplies)
                    .accessibilityIdentifier("settings.general.speakFirstmateReplies")
                SettingsNote(
                    text: "Speak new terminal and Telegram replies from the chosen home, even without a voice request.",
                    identifier: "settings.general.speakFirstmateRepliesNote"
                )
                Picker("Dismiss after reply", selection: $settings.autoDismissSeconds) {
                    ForEach(SettingsOptions.autoDismissSeconds, id: \.self) {
                        Text($0 == 0 ? "Never" : "\(Int($0)) s").tag($0)
                    }
                }
                .accessibilityIdentifier("settings.general.autoDismiss")
                Picker("Say “still working” after", selection: $settings.replyTimeoutSeconds) {
                    ForEach(SettingsOptions.replyTimeoutSeconds, id: \.self) { Text("\(Int($0)) s").tag($0) }
                }
                .accessibilityIdentifier("settings.general.replyTimeout")
                SettingsNote(
                    text: "A reply that takes longer is still spoken when it lands; "
                        + "the pill shows an orange dot meanwhile.",
                    identifier: "settings.general.replyNote"
                )
            }
            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled }, set: { launchAtLogin.set($0) }
                ))
                .accessibilityIdentifier("settings.general.launchAtLogin")
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("settings.general")
    }
}

/// The firstmate home: typed, chosen in a panel, or picked from the homes found on this Mac.
struct FirstmateHomeField: View {
    @Bindable var settings: AppSettings
    @State private var candidates: [String]
    private let discoversHomes: Bool

    init(settings: AppSettings, candidates: [String]? = nil) {
        self.settings = settings
        discoversHomes = candidates == nil
        _candidates = State(initialValue: candidates ?? FirstmateHome.candidates())
    }

    var body: some View {
        HStack {
            TextField("Home folder", text: $settings.firstmateHome, prompt: Text("~/.local/share/…/firstmate/<home>"))
                .accessibilityIdentifier("settings.general.firstmateHome")
            Button("Choose…") {
                let chosen = PathChooser.chooseFolder(
                    title: "Choose the firstmate home", startingAt: settings.firstmateHome
                )
                if let chosen {
                    settings.firstmateHome = chosen
                }
            }
            .accessibilityIdentifier("settings.general.chooseHome")
        }
        if !candidates.isEmpty {
            Picker("Found on this Mac", selection: foundSelection) {
                Text(settings.firstmateHome.isEmpty ? "Choose…" : "Custom").tag("")
                ForEach(candidates, id: \.self) { Text($0.abbreviatingHome).tag($0) }
            }
            .accessibilityIdentifier("settings.general.foundHomes")
        }
        status
        SettingsNote(
            text: "Notes go out with fm-inbox.sh note and replies come back from fm-inbox.sh receipts, "
                + "both in that home.",
            identifier: "settings.general.homeNote"
        )
        .onAppear {
            if discoversHomes {
                candidates = FirstmateHome.candidates()
            }
        }
    }

    private var foundSelection: Binding<String> {
        Binding(
            get: { candidates.contains(settings.firstmateHome) ? settings.firstmateHome : "" },
            set: {
                if !$0.isEmpty {
                    settings.firstmateHome = $0
                }
            }
        )
    }

    @ViewBuilder
    private var status: some View {
        if settings.firstmateHome.isEmpty {
            StatusText(
                tone: .warning, text: "No home chosen yet. Nothing can be sent to Firstmate until one is.",
                identifier: "settings.general.homeStatus"
            )
        } else if settings.firstmateHomeIsValid {
            StatusText(tone: .ready, text: "fm-inbox.sh found.", identifier: "settings.general.homeStatus")
        } else {
            StatusText(
                tone: .missing, text: "bin/fm-inbox.sh was not found in this folder.",
                identifier: "settings.general.homeStatus"
            )
        }
    }
}
