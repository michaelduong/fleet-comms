//  MessengerSettingsTests.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation
@testable import NotchVoice
import Testing

@MainActor
struct MessengerSettingsTests {
    @Test func defaultsPersistenceAndInvalidChoices() throws {
        let name = "FleetComms.messenger-tests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults)
        #expect(settings.messengerModel == .haiku)
        #expect(settings.fleetActiveRefresh == .minute)
        #expect(settings.fleetIdleRefresh == .fourMinutes)
        settings.messengerModel = .haiku
        settings.fleetActiveRefresh = .manual
        settings.fleetIdleRefresh = .fiveMinutes
        let restored = AppSettings(defaults: defaults)
        #expect(restored.messengerModel == .haiku)
        #expect(restored.fleetActiveRefresh == .manual)
        #expect(restored.fleetIdleRefresh == .fiveMinutes)
        defaults.set(MessengerModel.deepSeekFlash.rawValue, forKey: AppSettings.Key.messengerModel)
        #expect(AppSettings(defaults: defaults).messengerModel == .haiku)
        #expect(MessengerModel.offered == [.haiku])
        defaults.set("retired", forKey: AppSettings.Key.messengerModel)
        defaults.set("invalid", forKey: AppSettings.Key.fleetActiveRefresh)
        #expect(AppSettings(defaults: defaults).messengerModel == .haiku)
        #expect(AppSettings(defaults: defaults).fleetActiveRefresh == .minute)
    }

    @Test func staleWindowFollowsActiveRefresh() {
        #expect(FleetRefreshRate.minute.staleAfterSeconds == 300)
        #expect(FleetRefreshRate.fiveMinutes.staleAfterSeconds == 600)
        #expect(FleetRefreshRate.manual.seconds == nil)
        #expect(FleetRefreshRate.manual.staleAfterSeconds == 300)
        let fleet = FleetContext()
        fleet.configure(active: .fiveMinutes, idle: .manual)
        #expect(fleet.staleAfterSeconds == 600)
    }

    @Test func repliesRequireTheExactContract() throws {
        let valid = Data(#"{"handoff":false,"speak":"Two workers."}"#.utf8)
        #expect(try MessengerCommand.validated(valid).handoff == false)
        for malformed in [
            #"{"handoff":"false","speak":"Two."}"#, #"{"handoff":false}"#,
            #"{"handoff":false,"speak":""}"#, #"{"handoff":false,"speak":"Two.","extra":1}"#,
            "not JSON"
        ] {
            #expect(throws: (any Error).self) { try MessengerCommand.validated(Data(malformed.utf8)) }
        }
    }

    @Test func malformedClaudeResultFailsImmediately() {
        let line = #"{"type":"result","is_error":false,"structured_output":{"handoff":"no","speak":"Hi"}}"#
        #expect(AssistantWire.parse(line) == .failed("malformed"))
    }

    @Test func providerEnvelopesDecodeAndFailClosed() throws {
        let codex = #"{"item":{"type":"agent_message","text":"{\"handoff\":false,\"speak\":\"Two.\"}"}}"#
        let grok = #"{"structuredOutput":{"handoff":false,"speak":"Two."}}"#
        #expect(try MessengerCommand.reply(from: Data(grok.utf8), model: .grok).speak == "Two.")
        let openCode = #"{"type":"text","part":{"text":"{\"handoff\":true,\"speak\":\"\"}"}}"#
        #expect(try MessengerCommand.reply(from: Data(codex.utf8), model: .codexLuna).speak == "Two.")
        #expect(try MessengerCommand.reply(from: Data(openCode.utf8), model: .deepSeekFlash).handoff)
        #expect(throws: (any Error).self) {
            try MessengerCommand.reply(from: Data("{\"type\":\"error\"}".utf8), model: .grok)
        }
    }
}
