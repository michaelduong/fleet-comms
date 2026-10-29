//  SpeechSettingsTests.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import AppKit
import FluidAudio
import Foundation
@testable import NotchVoice
import Testing

@MainActor
struct SpeechSettingsTests {
    private func makeDefaults() throws -> (UserDefaults, () -> Void) {
        let name = "NotchVoice.speech-settings.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        return (defaults, { defaults.removePersistentDomain(forName: name) })
    }

    @Test func pickerIncludesEverySupportedEnglishMaleVoiceAndPreservesSavedChoice() throws {
        let supported = Set(KokoroAneConstants.englishVoices.filter { $0.hasPrefix("am_") || $0.hasPrefix("bm_") })
        let offered = Set(VoiceChoice.all.map(\.id))
        #expect(supported.isSubset(of: offered))
        #expect(offered.isSubset(of: Set(KokoroAneConstants.englishVoices)))
        #expect(offered.count == VoiceChoice.all.count)
        #expect(VoiceChoice.defaultID == "af_heart")
        let (defaults, cleanup) = try makeDefaults()
        defer { cleanup() }
        #expect(AppSettings(defaults: defaults).voiceID == "af_heart")
        for voice in VoiceChoice.all {
            defaults.set(voice.id, forKey: AppSettings.Key.voice)
            #expect(AppSettings(defaults: defaults).voiceID == voice.id)
        }
    }

    @Test func previewCanBeStoppedBeforeLoading() async throws {
        let preview = KokoroVoicePreview()
        preview.toggle(voiceID: "am_liam", speed: { .normal })
        #expect(preview.isPlaying)
        preview.toggle(voiceID: "am_liam", speed: { .normal })
        #expect(!preview.isPlaying)
        try await Task.sleep(for: .milliseconds(50))
        #expect(!preview.isPlaying)
        #expect(preview.errorMessage == nil)
        #expect(preview.activity == nil)
    }

    @Test func realtimeRequiresOptInOnFreshInstall() throws {
        let (defaults, cleanup) = try makeDefaults()
        defer { cleanup() }
        let settings = AppSettings(defaults: defaults)
        #expect(settings.voiceLane == .onDevice)
        #expect(!settings.isRealtimeEnabled(.chatGPT))
        #expect(!settings.isRealtimeEnabled(.grok))
        settings.setRealtimeEnabled(true, for: .chatGPT)
        settings.voiceLane = .chatGPTRealtime
        let restored = AppSettings(defaults: defaults)
        #expect(restored.isRealtimeEnabled(.chatGPT))
        #expect(!restored.isRealtimeEnabled(.grok))
        restored.setRealtimeEnabled(false, for: .chatGPT)
        #expect(restored.voiceLane == .onDevice)
        #expect(!AppSettings(defaults: defaults).isRealtimeEnabled(.chatGPT))
    }

    @Test(arguments: [VoiceLane.chatGPTRealtime, .grokVoice])
    func savedRealtimeChoiceSurvivesUpgrade(lane: VoiceLane) throws {
        let (defaults, cleanup) = try makeDefaults()
        defer { cleanup() }
        defaults.set(lane.rawValue, forKey: AppSettings.Key.voiceLane)
        let settings = AppSettings(defaults: defaults)
        let provider = try #require(lane.provider)
        #expect(settings.voiceLane == lane)
        #expect(settings.isRealtimeEnabled(provider))
        #expect(defaults.object(forKey: AppSettings.Key.realtimeEnabledPrefix + provider.id) == nil)
        settings.setRealtimeEnabled(false, for: provider)
        #expect(AppSettings(defaults: defaults).voiceLane == .onDevice)
        #expect(!AppSettings(defaults: defaults).isRealtimeEnabled(provider))
    }

    @Test func defaultsAndPersistence() throws {
        let (defaults, cleanup) = try makeDefaults()
        defer { cleanup() }
        let settings = AppSettings(defaults: defaults)
        #expect(settings.hangUpAfterQuietSeconds == 10)
        #expect(settings.speechSpeed == .brisk)
        #expect(settings.keepListeningAfterReply)
        #expect(SpeechSpeed.allCases.map(\.rawValue) == [1, 1.25, 1.5, 1.75, 2])
        settings.hangUpAfterQuietSeconds = 30
        #expect(AppSettings(defaults: defaults).hangUpAfterQuietSeconds == 30)
        defaults.set(-1, forKey: "hangUpAfterQuietSeconds")
        #expect(AppSettings(defaults: defaults).hangUpAfterQuietSeconds == 10)
        let model = AppModel(settings: settings)
        settings.speechSpeed = .double
        #expect(model.speaker.speed() == .double)
        settings.keepListeningAfterReply = false
        let restored = AppSettings(defaults: defaults)
        #expect(restored.speechSpeed == .double)
        #expect(!restored.keepListeningAfterReply)
        defaults.set(8, forKey: "speechSpeed")
        #expect(AppSettings(defaults: defaults).speechSpeed == .brisk)
    }

    @Test func menuKeepsOnlyQuickTogglesAndDrivesSettings() throws {
        let (defaults, cleanup) = try makeDefaults()
        defer { cleanup() }
        let settings = AppSettings(defaults: defaults)
        let model = AppModel(settings: settings)
        let window = SettingsWindowController(dependencies: SettingsDependencies(
            settings: settings, model: model, library: ModelLibrary(root: FileManager.default.temporaryDirectory),
            launchAtLogin: LaunchAtLogin(), developer: DeveloperActions(model: model), showOnboarding: {}
        ))
        let menu = StatusMenuBuilder(settings: settings, model: model, settingsWindow: window).makeMenu()
        let titles = menu.items.filter { !$0.isSeparatorItem }.map(\.title)
        #expect(titles == [
            "Talk to Firstmate (⌥ Space)", "Voice Lane", "Fast Assistant", "Read Whole Reply", "Settings…",
            "Quit Fleet Comms"
        ])
        let lanes = try #require(menu.items.first { $0.title == "Voice Lane" }?.submenu)
        #expect(lanes.items.dropFirst().allSatisfy { !$0.isEnabled })
        let assistant = try #require(menu.items.first { $0.title == "Fast Assistant" })
        #expect(assistant.state == .on)
        try NSApp.sendAction(#require(assistant.action), to: assistant.target, from: assistant)
        #expect(!settings.assistantEnabled)
        #expect(!AppSettings(defaults: defaults).assistantEnabled)
    }

    @Test func onboardingIsSkippedForAnExistingInstall() throws {
        let (defaults, cleanup) = try makeDefaults()
        defer { cleanup() }
        #expect(!AppSettings(defaults: defaults).onboardingCompleted)
        defaults.set("optionSpace", forKey: AppSettings.Key.hotkey)
        #expect(AppSettings(defaults: defaults).onboardingCompleted)
        defaults.set(false, forKey: AppSettings.Key.onboardingCompleted)
        #expect(!AppSettings(defaults: defaults).onboardingCompleted)
    }
}
