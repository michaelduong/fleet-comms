//  FleetRefreshTests.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation
@testable import NotchVoice
import Testing

@MainActor
struct FleetRefreshTests {
    @Test func manualIdleAndChangedIntervalsDriveTheSnapshot() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("fleet-refresh-\(UUID())")
        let bin = folder.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let script = bin.appendingPathComponent("fm-bearings-snapshot.sh")
        let body = """
        #!/bin/sh
        echo run >> "$FM_HOME/count"
        echo '{}'
        """
        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        var now = Date()
        let fleet = FleetContext(now: { now })
        fleet.configure(active: .manual, idle: .minute)
        fleet.start(home: folder.path)
        defer { fleet.stop() }
        try await Task.sleep(for: .milliseconds(1100))
        #expect(fleet.summary == nil)
        now = now.addingTimeInterval(601)
        try await waitForRefresh(fleet, at: now)
        #expect(fleet.summary != nil)
        #expect(try count(folder) == 1)
        // Returning to active/manual must not refresh automatically, even with old context.
        now = try #require(fleet.refreshedAt).addingTimeInterval(601)
        fleet.refreshIfStale()
        try await Task.sleep(for: .milliseconds(1100))
        #expect(try count(folder) == 1)
        var conversation = AssistantConversation()
        #expect(conversation.input(ownerSaid: "status?", context: fleet).fleetContext == nil)
        #expect(fleet.ageSeconds == 601)
        fleet.configure(active: .fiveMinutes, idle: .manual)
        #expect(conversation.input(ownerSaid: "status?", context: fleet).fleetContext == nil)
        fleet.refreshManually()
        try await waitForRefresh(fleet, at: now)
        #expect(try count(folder) == 2)
        #expect(conversation.input(ownerSaid: "status?", context: fleet).fleetContext != nil)
        now = now.addingTimeInterval(301)
        try await waitForRefresh(fleet, at: now)
        #expect(try count(folder) == 3)
    }

    private func waitForRefresh(_ fleet: FleetContext, at date: Date) async throws {
        for _ in 0 ..< 250 {
            if fleet.refreshedAt == date {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(fleet.refreshedAt == date)
    }

    private func count(_ folder: URL) throws -> Int {
        try String(contentsOf: folder.appendingPathComponent("count"), encoding: .utf8).split(separator: "\n").count
    }
}
