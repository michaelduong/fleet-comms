//  TalkIntent.swift
//  FleetCommsPhone
//
//  Created by Michael Duong on 11/17/26.

import AppIntents

/// Bound to the Action button (Settings › Action Button › Shortcut): opens the handset and starts listening.
struct TalkIntent: AppIntent {
    static let title: LocalizedStringResource = "Talk to Firstmate"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PhoneModel.shared.talkRequestedExternally = true
        return .result()
    }
}

struct FleetCommsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TalkIntent(),
            phrases: ["Talk to Firstmate with \(.applicationName)"],
            shortTitle: "Talk",
            systemImageName: "mic.fill"
        )
    }
}
