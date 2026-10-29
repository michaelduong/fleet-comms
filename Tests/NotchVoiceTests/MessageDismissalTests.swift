//  MessageDismissalTests.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation
@testable import NotchVoice
import Testing

@MainActor
struct MessageDismissalTests {
    @Test func messagesUseTheSettingsDelayWithoutOpeningFollowUpOrDismissingNewContent() async throws {
        let name = "message-dismissal-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: AppSettings.Key.fluidSpeechProAdopted)
        defaults.set("", forKey: AppSettings.Key.firstmateHome)
        let settings = AppSettings(defaults: defaults)
        settings.keepListeningAfterReply = true
        settings.autoDismissSeconds = 0.03
        let model = AppModel(settings: settings)
        defer { model.collapseTask?.cancel() }
        model.show(message: "Audio failed.")
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.state == .idle)
        #expect(model.followUpTask == nil)
        #expect(model.feed == nil)

        model.show(message: "Audio failed.", autoHideAfter: 0.03)
        settings.autoDismissSeconds = 0
        model.show(message: "Audio failed.")
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.state == .message("Audio failed."))

        model.show(message: "Audio failed.", autoHideAfter: 0.03)
        let reply = NotchState.reply(text: "A newer reply.", speaking: true, from: .firstMate)
        model.state = reply
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.state == reply)
    }
}
