//  AboutSettingsView.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import AppKit
import SwiftUI

struct AboutSettingsView: View {
    @ObservedObject var updater: AppUpdater

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                        .resizable()
                        .frame(width: 72, height: 72)
                        .accessibilityLabel("Fleet Comms app icon")
                        .accessibilityIdentifier("settings.about.icon")
                    Text(appName)
                        .font(.title2.bold())
                        .accessibilityIdentifier("settings.about.name")
                    Text("Version \(version) (build \(build))")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings.about.version")
                    Text("A voice companion for your agent fleet.")
                        .accessibilityIdentifier("settings.about.description")
                    Link("Project Repository", destination: UpdateConfiguration.repositoryURL)
                        .accessibilityIdentifier("settings.about.repository")
                }
                .padding(.vertical, 8)
            }
            Section("Updates") {
                Button("Check for Updates") {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)
                .accessibilityIdentifier("settings.about.checkUpdates")
                SettingsNote(
                    text: updater.configuration.isReady
                        ? "Sparkle checks for updates. Allow automatic checks when prompted to hear about new releases."
                        : UpdateConfiguration.holdMessage,
                    identifier: "settings.about.updateSetup"
                )
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("settings.about")
    }

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Fleet Comms"
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    }
}
