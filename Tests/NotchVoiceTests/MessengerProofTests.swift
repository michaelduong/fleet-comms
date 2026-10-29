//  MessengerProofTests.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation
@testable import NotchVoice
import Testing

struct MessengerProofTests {
    @Test func subscriptionLatency() async throws {
        guard let root = ProcessInfo.processInfo.environment["NOTCH_VOICE_MESSENGER_PROOF_ROOT"] else { return }
        let folder = URL(fileURLWithPath: root)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var results: [String] = []
        for model in MessengerModel.allCases {
            if let selected = ProcessInfo.processInfo.environment["NOTCH_VOICE_MESSENGER_PROOF_MODELS"],
               !selected.split(separator: ",").contains(Substring(model.rawValue)) {
                continue
            }
            guard let executable = model.executable else { continue }
            let assistant = ClaudeAssistant(executable: executable, model: model, directory: folder)
            var times: [Int] = []
            for question in ["How many workers are building?", "Are any workers blocked?", "Please fix the build."] {
                let input = AssistantTurnInput(
                    ownerSaid: question, fleetContext: "Synthetic fleet: two workers building; zero blocked.",
                    contextAgeSeconds: 10, recent: [], firstMateReplies: []
                )
                do {
                    let turn = try await assistant.ask(input)
                    times.append(turn.totalMs)
                    #expect(turn.reply.handoff == question.hasPrefix("Please"))
                    results.append("\(model.modelID) answer_ms=\(turn.totalMs) handoff=\(turn.reply.handoff)")
                } catch {
                    results.append("\(model.modelID) failed=\((error as? AssistantError)?.code ?? "error")")
                    Issue.record(error)
                    break
                }
            }
            await assistant.shutdown()
            if !times.isEmpty {
                results.append("\(model.modelID) median_ms=\(times.sorted()[times.count / 2])")
            }
        }
        try results.joined(separator: "\n").write(
            to: folder.appendingPathComponent("latency.txt"), atomically: true, encoding: .utf8
        )
    }
}
