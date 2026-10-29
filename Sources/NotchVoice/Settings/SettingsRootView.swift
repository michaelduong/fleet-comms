//  SettingsRootView.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import SwiftUI

/// The Settings window: a rail of sections on the left and a grouped form for the chosen one.
struct SettingsRootView: View {
    let dependencies: SettingsDependencies
    let updater: AppUpdater
    @Bindable var navigation: SettingsNavigation

    var body: some View {
        HStack(spacing: 0) {
            rail
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(navigation.section.title)
                .navigationSubtitle("Fleet Comms")
        }
        .frame(minWidth: 720, minHeight: 500)
        .accessibilityIdentifier("settings.root")
    }

    private var rail: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(SettingsSection.allCases) { section in
                RailRow(
                    title: section.title, symbol: section.symbol, selected: section == navigation.section,
                    identifier: "settings.sidebar.\(section.rawValue)"
                ) { navigation.section = section }
            }
            Spacer()
        }
        .padding(14)
        .frame(width: 190)
        .background(.quaternary.opacity(0.4))
        .accessibilityIdentifier("settings.sidebar")
    }

    @ViewBuilder
    private var detail: some View {
        switch navigation.section {
        case .general:
            GeneralSettingsView(settings: dependencies.settings, launchAtLogin: dependencies.launchAtLogin)
        case .voice:
            VoiceSettingsView(settings: dependencies.settings)
        case .assistant:
            AssistantSettingsView(settings: dependencies.settings)
        case .realtime:
            RealtimeSettingsView(settings: dependencies.settings)
        case .models:
            ModelsSettingsView(library: dependencies.library, settings: dependencies.settings)
        case .advanced:
            AdvancedSettingsView(dependencies: dependencies)
        case .about:
            AboutSettingsView(updater: updater)
        }
    }
}
