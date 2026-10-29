//  SessionReplyTests.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation
@testable import NotchVoice
import Testing

struct SessionReplyTests {
    private let start = Date(timeIntervalSince1970: 100)

    private func line(
        type: String = "assistant", text: String = "A final answer.", stop: String = "end_turn",
        id: String = "reply", timestamp: String = "2026-10-28T10:00:00.000Z", sidechain: Bool = false
    ) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "type": type, "uuid": id, "timestamp": timestamp, "isSidechain": sidechain,
            "message": ["id": id, "content": [["type": "text", "text": text]], "stop_reason": stop]
        ])
    }

    @Test func noOpAcknowledgementMatchesOnlyTheCompleteReply() throws {
        for text in ["Captain, shipshape.", "  CAPTAIN, SHIPSHAPE!? \n", "Shipshape", "shipshape…"] {
            #expect(SessionReplyReader.isNoOpAcknowledgement(text))
            var cursor = SessionReplyReader.Cursor()
            #expect(try cursor.consume(line(text: text), since: start) == nil)
        }
        for text in [
            "",
            "Captain, shipshape. The update is ready.",
            "Shipshape status",
            ".Shipshape",
            "Captain shipshape"
        ] {
            #expect(!SessionReplyReader.isNoOpAcknowledgement(text))
        }
    }

    @Test func onlyFinalMainSessionTextIsSpoken() throws {
        var cursor = SessionReplyReader.Cursor()
        #expect(try cursor.consume(line(stop: "tool_use"), since: start) == nil)
        #expect(try cursor.consume(line(stop: "max_tokens"), since: start) == nil)
        #expect(try cursor.consume(line(sidechain: true), since: start) == nil)
        #expect(try cursor.consume(line(timestamp: "1970-01-01T00:00:01Z"), since: start) == nil)
        #expect(try cursor.consume(line(), since: start)?.text == "A final answer.")
    }

    @Test func voiceMarkerInToolResultSuppressesUntilNextOwnerTurn() throws {
        var cursor = SessionReplyReader.Cursor()
        let toolResult = try JSONSerialization.data(withJSONObject: [
            "type": "user", "message": ["content": [[
                "type": "tool_result", "content": SessionReplyReader.voiceMarker + "\nA voice note."
            ]]]
        ])
        #expect(cursor.consume(toolResult, since: start) == nil)
        #expect(try cursor.consume(line(), since: start) == nil)
        let typed = try JSONSerialization.data(withJSONObject: [
            "type": "user", "message": ["content": [["type": "text", "text": "A typed message."]]]
        ])
        #expect(cursor.consume(typed, since: start) == nil)
        #expect(try cursor.consume(line(id: "typed-reply"), since: start) != nil)
    }

    @Test func textBlocksAreCombinedWithoutThinkingOrTools() throws {
        var cursor = SessionReplyReader.Cursor()
        let data = try JSONSerialization.data(withJSONObject: [
            "type": "assistant", "timestamp": "2026-10-28T10:00:00Z",
            "message": ["id": "blocks", "stop_reason": "end_turn", "content": [
                ["type": "thinking", "thinking": "Private reasoning"],
                ["type": "text", "text": "First paragraph."], ["type": "text", "text": "Last paragraph."]
            ]]
        ])
        #expect(cursor.consume(data, since: start)?.text == "First paragraph.\n\nLast paragraph.")
    }

    @Test func pollingHandlesPartialLinesRotationAndRestart() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let directory = root.appendingPathComponent("-scratch-home")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = directory.appendingPathComponent("first.jsonl")
        var data = try line(timestamp: "1970-01-01T00:00:01Z")
        data.append(0x0A)
        try data.write(to: file)
        let reader = SessionReplyReader(home: "/scratch/home", projectsRoot: root, startedAt: start)
        #expect(await reader.poll().isEmpty)
        let final = try line(id: "new")
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: final.prefix(final.count / 2))
        #expect(await reader.poll().isEmpty)
        try handle.write(contentsOf: final.suffix(final.count - final.count / 2) + Data([0x0A]))
        try handle.close()
        #expect(await reader.poll().map(\.id) == ["new"])
        #expect(await reader.poll().isEmpty)
        let rotated = directory.appendingPathComponent("second.jsonl")
        try (line(id: "rotated") + Data([0x0A])).write(to: rotated)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(1)],
            ofItemAtPath: rotated.path
        )
        #expect(await reader.poll().map(\.id) == ["rotated"])
        let restarted = SessionReplyReader(home: "/scratch/home", projectsRoot: root)
        #expect(await restarted.poll().isEmpty)
    }

    @Test @MainActor func repliesWaitWhileRecordingAndStopClearsTheQueue() throws {
        let name = "autospeak-queue-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: AppSettings.Key.fluidSpeechProAdopted)
        let model = AppModel(settings: AppSettings(defaults: defaults))
        model.state = .listening
        model.receiveSessionReply(.init(id: "one", text: "First reply."))
        model.receiveSessionReply(.init(id: "two", text: "Second reply."))
        #expect(model.state == .listening)
        #expect(!model.speaker.isSpeaking)
        #expect(model.autoSpeakReplies.map(\.id) == ["one", "two"])
        model.dismiss()
        #expect(model.autoSpeakReplies.isEmpty)
        #expect(model.state == .idle)
    }

    @Test @MainActor func realtimeLaneWithoutModelsStillDismissesAfterUnpromptedSpeech() async throws {
        let name = "autospeak-dismiss-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: AppSettings.Key.fluidSpeechProAdopted)
        let settings = AppSettings(defaults: defaults)
        settings.keepListeningAfterReply = true
        settings.voiceLane = .grokVoice
        settings.autoDismissSeconds = 0.02
        let model = AppModel(settings: settings)
        model.state = .reply(text: "The update is ready.", speaking: false, from: .firstMate)
        model.scheduleAutoDismiss()
        #expect(model.collapseTask != nil)
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.state == .idle)
    }

    @Test @MainActor func autoSpeakDefaultsOnAndExplicitOffPersists() throws {
        let name = "autospeak-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: AppSettings.Key.fluidSpeechProAdopted)
        defaults.set("", forKey: AppSettings.Key.firstmateHome)
        let settings = AppSettings(defaults: defaults)
        #expect(settings.speakFirstmateReplies)
        settings.speakFirstmateReplies = false
        #expect(!AppSettings(defaults: defaults).speakFirstmateReplies)
    }
}
