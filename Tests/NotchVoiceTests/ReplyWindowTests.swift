//  ReplyWindowTests.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/29/26.

import Foundation
@testable import NotchVoice
import Testing

@MainActor
struct ReplyWindowTests {
    @Test func silentReplyStaysOnlyWhileThePointerIsReallyOnIt() async throws {
        let (model, cleanup) = try makeModel(keepListening: false)
        defer { cleanup() }
        var over = true
        model.pointerOverPill = { over }
        let reply = NotchState.reply(text: "Done.", speaking: false, from: .firstMate)
        model.state = reply
        model.setPillHovered(true)
        model.scheduleAutoDismiss()
        try await Task.sleep(for: .milliseconds(90))
        #expect(model.state == reply)
        // The card was hidden under the pointer once, so no "left" ever arrives; the delay must notice.
        over = false
        try await Task.sleep(for: .milliseconds(90))
        #expect(model.state == .idle)
    }

    @Test func replyWindowFallsBackToDismissalWithoutModelsOnAnyLaneAndYieldsToAQuestion() async throws {
        let (model, cleanup) = try makeModel(keepListening: true)
        defer { cleanup() }
        model.settings.voiceLane = .grokVoice
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        model.settings.firstmateHome = home.path
        model.startQuestions()
        defer { model.stopQuestions() }
        try AskQuestionFixture.publish(in: home)
        model.questions.poll()
        model.state = .reply(text: "Done.", speaking: false, from: .firstMate)
        #expect(!model.modelsReady)
        model.scheduleAutoDismiss()
        try await Task.sleep(for: .milliseconds(120))
        #expect(model.state == .idle)
        #expect(model.displayState == .question)
    }

    private func makeModel(keepListening: Bool) throws -> (AppModel, () -> Void) {
        let name = "NotchVoice.reply-window.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.set(true, forKey: AppSettings.Key.fluidSpeechProAdopted)
        defaults.set("", forKey: AppSettings.Key.firstmateHome)
        let settings = AppSettings(defaults: defaults)
        settings.assistantEnabled = false
        settings.keepListeningAfterReply = keepListening
        settings.autoDismissSeconds = 0.03
        let model = AppModel(settings: settings)
        return (model, { model.collapseTask?.cancel(); defaults.removePersistentDomain(forName: name) })
    }
}
