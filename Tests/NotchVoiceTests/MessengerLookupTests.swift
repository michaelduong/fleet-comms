//  MessengerLookupTests.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Darwin
import Foundation
@testable import NotchVoice
import Testing

struct MessengerLookupTests {
    @Test func findsReportsBacklogAndImagePaths() throws {
        try withFixture { root, lookup in
            try put("Aurora appearance decision: keep automatic switching.", at: "task/report.md", root: root)
            try put("Aurora appearance work is planned.", at: "backlog.md", root: root)
            try put("image bytes are not model input", at: "aurora-appearance/shots/dark.png", root: root)
            let result = lookup.search("Where is the Aurora appearance plan and screenshots?")
            #expect(result.contains(root.appendingPathComponent("task/report.md").path))
            #expect(result.contains("keep automatic switching"))
            #expect(result.contains("backlog.md"))
            #expect(result.contains("aurora-appearance/shots/dark.png"))
            #expect(!result.contains("image bytes"))
        }
    }

    @Test func excludesSensitivePathsLinksAndSpecialFiles() throws {
        try withFixture { root, lookup in
            for path in [
                ".env",
                "config/report.md",
                "state/report.md",
                "credentials/report.md",
                "task/.hidden.md",
                "task/secret.md",
                "task/passwords.txt",
                "task/code.swift"
            ] {
                try put("Aurora appearance forbidden evidence.", at: path, root: root)
            }
            let outside = root.deletingLastPathComponent().appendingPathComponent("outside")
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            let target = outside.appendingPathComponent("report.md")
            try "Aurora appearance forbidden evidence.".write(to: target, atomically: true, encoding: .utf8)
            try FileManager.default.createSymbolicLink(
                at: root.appendingPathComponent("linked.md"),
                withDestinationURL: target
            )
            try FileManager.default.createSymbolicLink(
                at: root.appendingPathComponent("linked-folder"),
                withDestinationURL: outside
            )
            #expect(link(target.path, root.appendingPathComponent("hardlink.md").path) == 0)
            #expect(mkfifo(root.appendingPathComponent("pipe.md").path, 0o600) == 0)
            let result = lookup.search("Aurora appearance")
            #expect(!result.contains("forbidden evidence"))
            #expect(result.contains("No matching records"))
            let alias = root.deletingLastPathComponent().appendingPathComponent("alias")
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root)
            #expect(MessengerLookup(dataDirectory: alias).search("Aurora appearance").contains("No matching records"))
        }
    }

    @Test func boundedResultsFollowUpsAndActionFastPath() throws {
        try withFixture { root, lookup in
            for index in 0 ..< 20 {
                try put(
                    String(repeating: "Aurora appearance decision.\n", count: 500),
                    at: "task-\(index)/report.md",
                    root: root
                )
            }
            try put(String(repeating: "Aurora appearance", count: 30000), at: "oversized.md", root: root)
            let recent = [AssistantTurnInput.Exchange(owner: "Aurora appearance", assistant: "Saved.")]
            let followUp = AssistantTurnInput(
                ownerSaid: "Where are those?", fleetContext: nil, contextAgeSeconds: nil,
                recent: recent, firstMateReplies: []
            )
            let result = try #require(lookup.context(for: followUp))
            #expect(result.count < 12000)
            #expect(!result.contains("oversized.md"))
            #expect(result.components(separatedBy: "File: ").count == 5)
            let action = AssistantTurnInput(
                ownerSaid: "Please fix the build.",
                fleetContext: nil,
                contextAgeSeconds: nil,
                recent: [],
                firstMateReplies: []
            )
            #expect(lookup.context(for: action) == nil)
        }
    }

    @Test func recordsReachEveryModelWithoutEnablingTools() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var input = AssistantTurnInput(
            ownerSaid: "Where is the plan?",
            fleetContext: nil,
            contextAgeSeconds: nil,
            recent: [],
            firstMateReplies: []
        )
        input.pastWork = "Synthetic evidence from data/task/report.md"
        #expect(try AssistantPrompt.message(for: input, fresh: false, includeContext: false)
            .contains(#require(input.pastWork)))
        for model in MessengerModel.allCases {
            let command = try MessengerCommand(model: model, input: input, directory: directory)
            if model != .haiku {
                #expect(command.arguments.contains { $0.contains(input.pastWork!) })
            }
            if model == .haiku || model == .grok {
                let index = try #require(command.arguments.firstIndex(of: "--tools"))
                #expect(command.arguments[index + 1].isEmpty)
            }
        }
    }

    private func withFixture(_ body: (URL, MessengerLookup) throws -> Void) throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = parent.appendingPathComponent("data")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        try body(root, MessengerLookup(dataDirectory: root))
    }

    private func put(_ text: String, at path: String, root: URL) throws {
        let file = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
    }
}
