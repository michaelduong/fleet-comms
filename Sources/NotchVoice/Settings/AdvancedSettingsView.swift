//  AdvancedSettingsView.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import SwiftUI

struct AdvancedSettingsView: View {
    let dependencies: SettingsDependencies

    private var settings: AppSettings {
        dependencies.settings
    }

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Firstmate") {
                TextField("Inbox script", text: $settings.inboxScript, prompt: Text("<home>/bin/fm-inbox.sh"))
                    .accessibilityIdentifier("settings.advanced.inboxScript")
                SettingsNote(
                    text: "Only for a home whose inbox script lives somewhere else. "
                        + "Empty uses bin/fm-inbox.sh in the home.",
                    identifier: "settings.advanced.inboxScriptNote"
                )
            }
            Section("Diagnostics") {
                LabeledContent("Event log", value: EventLog.url.path.abbreviatingHome)
                    .accessibilityIdentifier("settings.advanced.eventLogPath")
                Button("Show Event Log in Finder", action: dependencies.developer.revealEventLog)
                    .accessibilityIdentifier("settings.advanced.showEventLog")
                SettingsNote(
                    text: "Note and turn ids, decisions and millisecond timings only; never what was said or heard.",
                    identifier: "settings.advanced.eventLogNote"
                )
            }
            Section("Developer") {
                Button("Feed WAV File as Speech…", action: dependencies.developer.chooseWav)
                    .accessibilityIdentifier("settings.advanced.feedWav")
                SettingsNote(
                    text: "Plays a recording through the real listening pipeline instead of the microphone. Notes sent "
                        + "this way start with “TEST notch-voice:”. The same works on launch with --feed-wav <path>.",
                    identifier: "settings.advanced.feedWavNote"
                )
                Button("Show Onboarding Again", action: dependencies.showOnboarding)
                    .accessibilityIdentifier("settings.advanced.showOnboarding")
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("settings.advanced")
    }
}
