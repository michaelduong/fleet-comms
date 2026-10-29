//  MessengerLookupProofTests.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation
@testable import NotchVoice
import Testing

struct MessengerLookupProofTests {
    @Test func liveLookupAndForward() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let root = environment["FLEET_COMMS_LOOKUP_PROOF_ROOT"],
              let question = environment["FLEET_COMMS_LOOKUP_PROOF_QUESTION"] else { return }
        let folder = URL(fileURLWithPath: root)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let model = MessengerModel(rawValue: environment["FLEET_COMMS_LOOKUP_PROOF_MODEL"] ?? "haiku") ?? .haiku
        let executable = try #require(model.executable)
        let dataDirectory = environment["FLEET_COMMS_LOOKUP_PROOF_DATA"].map { URL(fileURLWithPath: $0) }
        let assistant = ClaudeAssistant(
            executable: executable, model: model, directory: folder, dataDirectory: dataDirectory
        )
        var lines: [String] = []
        do {
            for request in [question, "Please fix the build."] {
                let input = AssistantTurnInput(
                    ownerSaid: request, fleetContext: nil, contextAgeSeconds: nil, recent: [], firstMateReplies: []
                )
                let start = Date()
                let turn = try await assistant.ask(input)
                lines.append("elapsed_ms=\(Int(Date().timeIntervalSince(start) * 1000)) " +
                    "handoff=\(turn.reply.handoff) speak=\(turn.reply.speak)")
                if request != question {
                    #expect(turn.reply.handoff)
                } else if let expected = environment["FLEET_COMMS_LOOKUP_PROOF_EXPECTED_FOLDER"] {
                    #expect(!turn.reply.handoff)
                    #expect(turn.reply.speak.contains(expected))
                }
            }
        } catch {
            await assistant.shutdown()
            throw error
        }
        await assistant.shutdown()
        try lines.joined(separator: "\n").write(
            to: folder.appendingPathComponent("answers.txt"), atomically: true, encoding: .utf8
        )
    }
}
