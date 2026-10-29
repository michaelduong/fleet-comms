//  AskQuestionFixture.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/29/26.

import Foundation
@testable import NotchVoice

enum AskQuestionFixture {
    /// Publishes one two-option question under `home`, as the hook would, and returns its folder.
    @discardableResult
    static func publish(in home: URL) throws -> URL {
        let folder = home.appendingPathComponent(
            "state/fleet-comms-questions/\(UUID().uuidString)", isDirectory: true
        )
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let request = AskRequest(
            id: folder.lastPathComponent, agent: "claude-test", sessionID: "scratch", toolUseID: "tool",
            expiresAt: Date().timeIntervalSince1970 + 120,
            questions: [AskQuestion(question: "Ship it?", header: "Ship", options: [
                .init(label: "Yes", description: nil), .init(label: "No", description: nil)
            ], multiSelect: nil)]
        )
        try JSONEncoder().encode(request).write(to: folder.appendingPathComponent("request.json"))
        return folder
    }
}
