//  AssistantSettingsView.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import SwiftUI

struct AssistantSettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section("Fast assistant") {
                Toggle("Answer quick questions with the messenger", isOn: $settings.assistantEnabled)
                    .accessibilityIdentifier("settings.assistant.enabled")
                SettingsNote(
                    text: "The messenger answers quick questions and hands real work to Firstmate. "
                        + "Every model uses its CLI subscription, with no tools and a 20-second answer limit.",
                    identifier: "settings.assistant.note"
                )
            }
            Section("Messenger model") {
                Picker("Model", selection: $settings.messengerModel) {
                    ForEach(MessengerModel.offered) { model in
                        Text(model.title + (available(model) ? "" : " (CLI missing)"))
                            .tag(model)
                            .disabled(!available(model))
                    }
                }
                .accessibilityIdentifier("settings.assistant.model")
                SettingsNote(
                    text: "Only models answering within a measured 5-second median are offered. "
                        + "Claude Haiku currently qualifies; the other tested models exceeded that limit.",
                    identifier: "settings.assistant.modelNote"
                )
            }
            Section("Fleet context refresh") {
                refreshPicker("While active", selection: $settings.fleetActiveRefresh, id: "activeRefresh")
                refreshPicker("After 10 minutes idle", selection: $settings.fleetIdleRefresh, id: "idleRefresh")
                Button("Refresh now") { settings.onChange?(.refreshFleet) }
                    .accessibilityIdentifier("settings.assistant.refreshNow")
                SettingsNote(
                    text: "Off disables automatic refresh in that state. Manual context expires after 5 minutes; "
                        +
                        "otherwise the messenger accepts context for at least 5 minutes or twice the active interval.",
                    identifier: "settings.assistant.refreshNote"
                )
            }
            Section("Claude CLI") {
                status
                HStack {
                    TextField(
                        "Path", text: $settings.claudePath, prompt: Text(settings.resolvedClaudePath.abbreviatingHome)
                    )
                    .accessibilityIdentifier("settings.assistant.claudePath")
                    Button("Choose…") {
                        if let path = PathChooser.chooseFile(title: "Choose the claude executable") {
                            settings.claudePath = path
                        }
                    }
                    .accessibilityIdentifier("settings.assistant.chooseClaude")
                }
                SettingsNote(
                    text: "Leave the path empty to use the first claude found in ~/.local/bin, ~/.claude/local, "
                        + "/opt/homebrew/bin or /usr/local/bin. The CLI runs on its own signed-in subscription; "
                        + "no API key is read or sent.",
                    identifier: "settings.assistant.pathNote"
                )
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("settings.assistant")
    }

    private func available(_ model: MessengerModel) -> Bool {
        model == .haiku ? settings.claudeCLIFound : model.executable != nil
    }

    private func refreshPicker(_ title: String, selection: Binding<FleetRefreshRate>, id: String) -> some View {
        Picker(title, selection: selection) {
            ForEach(FleetRefreshRate.allCases) { rate in
                Text(rate.title).tag(rate)
            }
        }
        .accessibilityIdentifier("settings.assistant." + id)
    }

    @ViewBuilder
    private var status: some View {
        if settings.claudeCLIFound {
            StatusText(
                tone: .ready, text: "Found at \(settings.resolvedClaudePath.abbreviatingHome).",
                identifier: "settings.assistant.status"
            )
        } else {
            StatusText(
                tone: settings.assistantEnabled ? .warning : .neutral,
                text: "Not found. Install Claude Code and sign in with claude login; until then the "
                    + "assistant is skipped and your words go straight to Firstmate.",
                identifier: "settings.assistant.status"
            )
        }
    }
}
