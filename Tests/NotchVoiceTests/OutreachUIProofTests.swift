//  OutreachUIProofTests.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import AppKit
@testable import NotchVoice
import SwiftUI
import Testing

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["FLEET_COMMS_OUTREACH_UI_ROOT"] != nil))
@MainActor
struct OutreachUIProofTests {
    @Test func settingsRenderInLightAndDark() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["FLEET_COMMS_OUTREACH_UI_ROOT"])
        let root = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let name = "outreach-ui-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: AppSettings.Key.fluidSpeechProAdopted)
        defaults.set("", forKey: AppSettings.Key.firstmateHome)
        let settings = AppSettings(defaults: defaults)
        for dark in [false, true] {
            for choice in OutreachVoice.allCases {
                settings.outreachVoice = choice
                let window = NSWindow(
                    contentRect: NSRect(x: 100, y: 100, width: 580, height: 1100),
                    styleMask: [.titled], backing: .buffered, defer: false
                )
                window.title = "Realtime Settings"
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                window.contentView = NSHostingView(rootView: RealtimeSettingsView(settings: settings)
                    .environment(\.colorScheme, dark ? .dark : .light))
                window.orderFront(nil)
                try await Task.sleep(for: .milliseconds(750))
                let file = root.appendingPathComponent("\(choice.rawValue)-\(dark ? "dark" : "light").png")
                UICapture.write(window, to: file)
                #expect(FileManager.default.fileExists(atPath: file.path))
                window.orderOut(nil)
            }
        }
    }
}
