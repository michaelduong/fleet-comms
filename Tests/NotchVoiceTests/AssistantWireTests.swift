//  AssistantWireTests.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation
@testable import NotchVoice
import Testing

struct AssistantWireTests {
    @Test func structuredResultBecomesAReply() {
        let line = """
        {"type":"result","subtype":"success","is_error":false,"result":"{}",\
        "structured_output":{"handoff":true,"speak":"That changes the repo."}}
        """
        #expect(AssistantWire.parse(line) == .reply(AssistantReply(handoff: true, speak: "That changes the repo.")))
    }

    @Test func errorResultFails() {
        let line = #"{"type":"result","subtype":"error_max_turns","is_error":true}"#
        #expect(AssistantWire.parse(line) == .failed("error_max_turns"))
    }

    @Test func streamedDeltaMarksFirstToken() {
        let line = #"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta"}}}"#
        #expect(AssistantWire.parse(line) == .delta)
        #expect(AssistantWire.parse(#"{"type":"stream_event","event":{"type":"message_start"}}"#) == .other)
        #expect(AssistantWire.parse(#"{"type":"system","subtype":"init"}"#) == .other)
        #expect(AssistantWire.parse("not json") == .other)
    }

    @Test func userLineIsOneJSONLine() throws {
        let data = try AssistantWire.userLine("say \"hi\"\nplease")
        #expect(data.last == 0x0A)
        #expect(data.dropLast().contains(0x0A) == false)
        let object = try #require(JSONSerialization.jsonObject(with: data.dropLast()) as? [String: Any])
        let message = try #require(object["message"] as? [String: Any])
        #expect(message["content"] as? String == "say \"hi\"\nplease")
    }

    @Test func promptRepeatsHistoryOnlyToAFreshProcess() {
        let input = AssistantTurnInput(
            ownerSaid: "and now?",
            fleetContext: "Underway (1):",
            contextAgeSeconds: 30,
            recent: [.init(owner: "hi", assistant: "Hello.")],
            firstMateReplies: []
        )
        let fresh = AssistantPrompt.message(for: input, fresh: true, includeContext: true)
        #expect(fresh.contains("<earlier_conversation>"))
        #expect(fresh.contains("<fleet_context age_seconds=\"30\">\nUnderway (1):"))
        let warm = AssistantPrompt.message(for: input, fresh: false, includeContext: false)
        #expect(!warm.contains("earlier_conversation"))
        #expect(warm.contains("<fleet_context unchanged age_seconds=\"30\"/>"))
        #expect(warm.hasSuffix("<owner_said>and now?</owner_said>"))
    }

    @Test func missingContextIsStated() {
        let input = AssistantTurnInput(
            ownerSaid: "status?", fleetContext: nil, contextAgeSeconds: nil, recent: [], firstMateReplies: ["Done."]
        )
        let message = AssistantPrompt.message(for: input, fresh: true, includeContext: true)
        #expect(message.contains("<fleet_context unavailable/>"))
        #expect(message.contains("<first_mate_replied>\nDone.\n</first_mate_replied>"))
    }
}
