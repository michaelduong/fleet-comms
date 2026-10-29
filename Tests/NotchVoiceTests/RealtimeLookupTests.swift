//  RealtimeLookupTests.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation
@testable import NotchVoice
import Testing

@MainActor
struct RealtimeLookupTests {
    @Test(arguments: [RealtimeProvider.chatGPT, .grok])
    func bothLanesExposeOnlyQuestionForLookup(provider: RealtimeProvider) throws {
        let update = RealtimeWire.sessionUpdate(.init(
            provider: provider, voice: "test", instructions: "", silenceMs: 800
        ))
        let object = try #require(JSONSerialization.jsonObject(with: Data(update.utf8)) as? [String: Any])
        let session = try #require(object["session"] as? [String: Any])
        let tools = try #require(session["tools"] as? [[String: Any]])
        #expect(tools.compactMap { $0["name"] as? String } == [
            RealtimePrompt.handoffToolName, RealtimePrompt.lookupToolName
        ])
        let tool = try #require(tools.last)
        let parameters = try #require(tool["parameters"] as? [String: Any])
        let properties = try #require(parameters["properties"] as? [String: Any])
        #expect(Set(properties.keys) == ["question"])
        #expect(parameters["additionalProperties"] as? Bool == false)
    }

    @Test func toolReadsSharedEvidenceWithoutHandoffOrWiderPaths() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let data = root.appendingPathComponent("data")
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "Aurora appearance decision.".write(
            to: data.appendingPathComponent("report.md"), atomically: true, encoding: .utf8
        )
        let outside = root.appendingPathComponent("outside.md")
        try "Aurora appearance forbidden evidence.".write(to: outside, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: data.appendingPathComponent("linked.md"),
            withDestinationURL: outside
        )
        let call = makeCall(data: data)
        let delegate = RealtimeLookupDelegate()
        call.delegate = delegate
        let result = await output(
            call,
            name: RealtimePrompt.lookupToolName,
            arguments: #"{"question":"Aurora appearance","path":"/"}"#
        )
        #expect(result.contains(data.appendingPathComponent("report.md").path))
        #expect(!result.contains("forbidden evidence"))
        #expect(delegate.handoffs.isEmpty)
        #expect(await output(
            call,
            name: RealtimePrompt.handoffToolName,
            arguments: #"{"request":"Please fix the build."}"#
        ) == "passed")
        #expect(delegate.handoffs == ["Please fix the build."])
    }

    @Test func malformedUnavailableAndUnknownToolsStayReadOnly() async {
        let call = makeCall()
        let delegate = RealtimeLookupDelegate()
        call.delegate = delegate
        #expect(await output(
            call,
            name: RealtimePrompt.lookupToolName,
            arguments: #"{"question":"  "}"#
        ).contains("non-empty question"))
        #expect(await output(
            call,
            name: RealtimePrompt.lookupToolName,
            arguments: #"{"question":"Aurora"}"#
        ).contains("unavailable"))
        #expect(await output(call, name: "read_file", arguments: #"{"request":"/"}"#).contains("Unknown tool"))
        #expect(delegate.handoffs.isEmpty)
    }

    @Test(arguments: [false, true])
    func lookupKeepsCallOpenUntilToolCompletes(afterOutreach: Bool) async {
        let call = makeCall(afterOutreach: afterOutreach)
        call.handle(.responseCreated)
        call.handle(.functionCall(
            callID: "lookup",
            name: RealtimePrompt.lookupToolName,
            arguments: #"{"question":"Aurora"}"#
        ))
        #expect(call.pendingTools == 1)
        call.handle(.responseDone(status: "completed"))
        call.checkForIdle(at: Date().addingTimeInterval(60))
        #expect(!call.ended)
        for _ in 0 ..< 100 where call.pendingTools > 0 {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(call.pendingTools == 0)
        #expect(call.toolResponsePending)
        call.end()
    }

    private func makeCall(data: URL? = nil, afterOutreach: Bool = false) -> RealtimeCall {
        let outreach = afterOutreach ? RealtimeOutreach(reply: .init(id: "test", text: "An update.")) : nil
        outreach?.completed = true
        return RealtimeCall(
            provider: .grok,
            voice: "rex",
            source: .wav(URL(fileURLWithPath: "/unused")),
            silenceSeconds: 0.8, outreach: outreach,
            dataDirectory: data
        ) { "" }
    }

    private func output(_ call: RealtimeCall, name: String, arguments: String) async -> String {
        await call.toolOutput(
            name: name,
            arguments: arguments,
            endpoint: Endpoint(detected: Date(), lastSpeech: Date()),
            turnID: "test"
        )
    }
}

@MainActor
final class RealtimeLookupDelegate: RealtimeCallDelegate {
    var handoffs: [String] = []
    var toolCalls: [[String: String]] = []
    var answer = ""
    var failure: RealtimeError?
    var heardAudio = false

    func call(_ call: RealtimeCall, phase: CallPhase) {
        if phase == .speaking {
            heardAudio = true
        }
    }

    func call(_ call: RealtimeCall, level: Float) {}
    func call(_ call: RealtimeCall, text: String) {
        if !call.spoken.isEmpty {
            answer = call.spoken
        }
    }

    func call(_ call: RealtimeCall, handOff request: String, endpoint: Endpoint) async -> String? {
        handoffs.append(request)
        return "test-note"
    }

    func call(_ call: RealtimeCall, endedWith error: RealtimeError?) {
        failure = error
    }
}
