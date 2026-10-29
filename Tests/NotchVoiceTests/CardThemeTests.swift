//  CardThemeTests.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation
@testable import NotchVoice
import Testing

@MainActor
struct CardThemeTests {
    @Test func themeDefaultsToDarkAndPersistsAcrossLaunches() throws {
        let name = "NotchVoice.card-theme.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("", forKey: AppSettings.Key.firstmateHome)
        let settings = AppSettings(defaults: defaults)
        #expect(settings.cardTheme == .dark)
        settings.cardTheme = .glass
        #expect(AppSettings(defaults: defaults).cardTheme == .glass)
        settings.cardTheme = .dark
        #expect(AppSettings(defaults: defaults).cardTheme == .dark)
        defaults.set("unknown", forKey: AppSettings.Key.cardTheme)
        #expect(AppSettings(defaults: defaults).cardTheme == .dark)
    }
}
