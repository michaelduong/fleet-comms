//  SettingsWindowController.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import AppKit
import SwiftUI

/// The Settings window, opened from the status menu, onboarding or a launch argument.
@MainActor
final class SettingsWindowController {
    let navigation = SettingsNavigation()
    private let updater: AppUpdater
    private let dependencies: SettingsDependencies
    private(set) var window: NSWindow?

    init(dependencies: SettingsDependencies, updater: AppUpdater = AppUpdater()) {
        self.updater = updater
        self.dependencies = dependencies
    }

    func show(_ section: SettingsSection? = nil) {
        if let section {
            navigation.section = section
        }
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let root = SettingsRootView(dependencies: dependencies, updater: updater, navigation: navigation)
        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        // SwiftUI takes the title over once the view appears; this covers the first frame.
        window.title = navigation.section.title
        window.subtitle = "Fleet Comms"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 780, height: 560))
        window.center()
        window.setFrameAutosaveName("FleetCommsSettings")
        window.setAccessibilityIdentifier("settings.window")
        return window
    }
}
