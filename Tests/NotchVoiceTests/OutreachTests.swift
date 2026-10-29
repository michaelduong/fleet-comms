//  OutreachTests.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation
@testable import NotchVoice
import Testing

@MainActor
struct OutreachTests {
    @Test func settingIsIndependentAndPersistsWithExistingVoiceOption() throws {
        let name = "outreach-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: AppSettings.Key.fluidSpeechProAdopted)
        defaults.set("", forKey: AppSettings.Key.firstmateHome)
        let settings = AppSettings(defaults: defaults)
        #expect(settings.outreachVoice == .kokoro)
        settings.voiceLane = .onDevice
        #expect(settings.outreachHangUpSeconds == 25)
        settings.outreachHangUpSeconds = 30
        settings.outreachVoice = .grokVoice
        settings.setRealtimeVoice("ara", for: .grok)
        let restored = AppSettings(defaults: defaults)
        #expect(restored.outreachVoice == .grokVoice)
        #expect(restored.outreachHangUpSeconds == 30)
        #expect(restored.voiceLane == .onDevice)
        #expect(restored.realtimeVoice(.grok) == "ara")
        settings.outreachVoice = .gptRealtime
        #expect(AppSettings(defaults: defaults).outreachVoice.provider == .chatGPT)
    }

    @Test func sessionHasNoTurnDetectionOrToolsAndTextIsUnchanged() throws {
        let data = Data(OutreachWire.sessionUpdate(voice: "rex").utf8)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let session = try #require(object["session"] as? [String: Any])
        let audio = try #require(session["audio"] as? [String: Any])
        let input = try #require(audio["input"] as? [String: Any])
        #expect(input["turn_detection"] is NSNull)
        #expect((session["tools"] as? [Any])?.isEmpty == true)
        #expect(session["tool_choice"] as? String == "none")
        let text = "Read exactly this. Do not add an introduction."
        let response = try #require(JSONSerialization.jsonObject(
            with: Data(RealtimeWire.userText(text).utf8)
        ) as? [String: Any])
        let item = try #require(response["item"] as? [String: Any])
        let content = try #require(item["content"] as? [[String: Any]])
        #expect(content.first?["text"] as? String == text)
        #expect(item["role"] as? String == "user")
    }

    @Test func addedOmittedOrReorderedWordsAreRejected() {
        #expect(OutreachWire.matches("The update is ready!", text: "The update is ready."))
        #expect(!OutreachWire.matches("Sure. The update is ready.", text: "The update is ready."))
        #expect(!OutreachWire.matches("The update.", text: "The update is ready."))
        #expect(!OutreachWire.matches("Ready is the update.", text: "The update is ready."))
        #expect(!OutreachWire.matches("", text: ""))
    }

    @Test func readingPreservesLinkLabelsAndCompleteTargetsWithoutCitationSyntax() {
        let source = "Read [the change](https://example.com/pull/28). Keep `/tmp/proof` on screen."
        let reading = OutreachWire.readingText(source)
        #expect(reading == "Read the change https colon slash slash example dot com slash pull slash 28. " +
            "Keep `/tmp/proof` on screen.")
        #expect(!OutreachWire.matches("Read the change example.com. Keep /tmp/proof on screen.", text: reading))
        #expect(OutreachWire.readingText("An update is ready.") == "An update is ready.")
        let two = OutreachWire.readingText("https://a.test/x?y=2&z=3 https://b.test/a-b#part")
        #expect(two == "https colon slash slash a dot test slash x question mark y equals 2 ampersand z equals 3 " +
            "https colon slash slash b dot test slash a dash b hash part")
    }

    @Test func changedReadingAndProviderErrorsAreRejected() throws {
        let reply = SessionReplyReader.Reply(id: "proof", text: "An update.")
        let reading = RealtimeOutreach(reply: reply)
        _ = try reading.consume(.transcriptDelta("Sure. An update."))
        _ = try reading.consume(.audioDelta(itemID: "item", audio: RealtimePCM.encode([0.1, 0.2])))
        #expect(throws: RealtimeError.readingMismatch) {
            try reading.consume(.responseDone(status: "completed"))
        }
        for event in [
            RealtimeWire.Event.error(code: "bad_request"),
            .responseDone(status: "failed")
        ] {
            #expect(throws: RealtimeError.readingFailed) {
                try RealtimeOutreach(reply: reply).consume(event)
            }
        }
        #expect(throws: RealtimeError.readingMismatch) {
            try RealtimeOutreach(reply: reply).consume(.responseDone(status: "completed"))
        }
    }

    @Test func exactReadingIsAcceptedAndSilenceIsRejected() throws {
        let reading = RealtimeOutreach(reply: .init(id: "proof", text: "An update."))
        _ = try reading.consume(.transcriptDelta("An update!"))
        _ = try reading.consume(.audioDelta(itemID: "item", audio: RealtimePCM.encode([0.2, -0.2])))
        #expect(try reading.consume(.responseDone(status: "completed"))?.count == 2)
        let silence = RealtimeOutreach(reply: .init(id: "proof", text: "An update."))
        _ = try silence.consume(.transcriptDelta("An update."))
        _ = try silence.consume(.audioDelta(itemID: "item", audio: RealtimePCM.encode([0, 0])))
        #expect(throws: RealtimeError.readingFailed) {
            try silence.consume(.responseDone(status: "completed"))
        }
    }

    @Test func readingDeadlineEndsCallAndNormalIdleWaitsUntilReadingFinishes() async throws {
        let reading = RealtimeOutreach(reply: .init(id: "proof", text: "An update."))
        let call = RealtimeCall(
            provider: .grok,
            voice: "rex",
            source: .wav(URL(fileURLWithPath: "/unused")),
            silenceSeconds: 0.8,
            idleHangUp: 25,
            outreach: reading
        ) { "" }
        call.lastActivity = Date().addingTimeInterval(-100)
        call.checkForIdle()
        #expect(!call.ended)
        call.watchOutreach(seconds: 0.01)
        try await Task.sleep(for: .milliseconds(50))
        #expect(call.ended)
    }

    @Test(arguments: [RealtimeProvider.grok, .chatGPT])
    func outreachQuietWindowStartsAfterPlayback(provider: RealtimeProvider) {
        let reading = RealtimeOutreach(reply: .init(id: "proof", text: "An update."))
        let call = RealtimeCall(
            provider: provider,
            voice: "rex",
            source: .wav(URL(fileURLWithPath: "/unused")),
            silenceSeconds: 0.8,
            idleHangUp: 25,
            outreach: reading
        ) { "" }
        reading.completed = true
        call.lastActivity = Date()
        call.checkForIdle(at: call.lastActivity.addingTimeInterval(24.99))
        #expect(!call.ended)
        call.checkForIdle(at: call.lastActivity.addingTimeInterval(25.01))
        #expect(call.ended)
    }

    @Test(arguments: [RealtimeProvider.grok, .chatGPT])
    func endControlDismissesOutreachCall(provider: RealtimeProvider) throws {
        let name = "outreach-end-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: AppSettings.Key.fluidSpeechProAdopted)
        defaults.set("", forKey: AppSettings.Key.firstmateHome)
        let model = AppModel(settings: AppSettings(defaults: defaults))
        let reading = RealtimeOutreach(reply: .init(id: "proof", text: "An update."))
        reading.completed = true
        let call = RealtimeCall(
            provider: provider, voice: "", source: .wav(URL(fileURLWithPath: "/unused")),
            silenceSeconds: 0.8, idleHangUp: 25, outreach: reading
        ) { "" }
        call.delegate = model
        model.call = call
        model.isAutoSpeaking = true
        model.autoSpeakID = UUID()
        model.state = .call(.listening)
        model.hangUp()
        #expect(call.ended)
        #expect(model.call == nil)
        #expect(model.state == .idle)
        #expect(!model.isAutoSpeaking)
        #expect(model.autoSpeakID == nil)
    }

    @Test func voiceNoteReplyWaitsForInitialReadingWithoutCancellingCall() throws {
        let name = "outreach-queue-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: AppSettings.Key.fluidSpeechProAdopted)
        defaults.set("", forKey: AppSettings.Key.firstmateHome)
        let settings = AppSettings(defaults: defaults)
        settings.readWholeReply = false
        let model = AppModel(settings: settings)
        let reading = RealtimeOutreach(reply: .init(id: "outreach", text: "An update."))
        let call = RealtimeCall(
            provider: .grok,
            voice: "rex",
            source: .wav(URL(fileURLWithPath: "/unused")),
            silenceSeconds: 0.8,
            outreach: reading
        ) { "" }
        model.call = call
        model.isAutoSpeaking = true
        model.autoSpeakID = UUID()
        model.state = .call(.connecting)
        model.receive(.init(noteID: "voice-note", body: "The requested answer.", seenAt: Date()))
        #expect(model.call === call)
        #expect(!call.ended)
        #expect(call.announcements.count == 1)
        model.stopAutoSpeech()
        #expect(call.ended)
        #expect(model.call == nil)
        #expect(model.queuedReplies.count == 1)
    }
}
