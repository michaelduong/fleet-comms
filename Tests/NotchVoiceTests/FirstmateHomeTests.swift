//  FirstmateHomeTests.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation
@testable import NotchVoice
import Testing

struct FirstmateHomeTests {
    private func makeRoot(homes: [String], broken: [String] = []) throws -> String {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("fm-homes-\(UUID().uuidString)").path
        for name in homes {
            let bin = root + "/" + name + "/bin"
            try FileManager.default.createDirectory(atPath: bin, withIntermediateDirectories: true)
            try "#!/bin/sh\n".write(toFile: bin + "/fm-inbox.sh", atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin + "/fm-inbox.sh")
        }
        for name in broken {
            try FileManager.default.createDirectory(atPath: root + "/" + name, withIntermediateDirectories: true)
        }
        return root
    }

    @Test func aSingleHomeIsTheDefault() throws {
        let root = try makeRoot(homes: ["alpha"], broken: ["no-scripts"])
        defer { try? FileManager.default.removeItem(atPath: root) }
        #expect(FirstmateHome.candidates(under: root, environment: [:]) == [root + "/alpha"])
        #expect(FirstmateHome.defaultHome(under: root, environment: [:]) == root + "/alpha")
    }

    @Test func severalHomesLeaveTheChoiceToOnboarding() throws {
        let root = try makeRoot(homes: ["beta", "alpha"])
        defer { try? FileManager.default.removeItem(atPath: root) }
        #expect(FirstmateHome.candidates(under: root, environment: [:]) == [root + "/alpha", root + "/beta"])
        #expect(FirstmateHome.defaultHome(under: root, environment: [:]).isEmpty)
    }

    @Test func environmentHomeComesFirstAndMissingRootIsEmpty() throws {
        let root = try makeRoot(homes: ["alpha"])
        defer { try? FileManager.default.removeItem(atPath: root) }
        let environment = ["FM_HOME": root + "/alpha"]
        #expect(FirstmateHome.candidates(under: root, environment: environment) == [root + "/alpha"])
        #expect(FirstmateHome.candidates(under: root + "/missing", environment: ["FM_HOME": "/nowhere"]).isEmpty)
        #expect(FirstmateHome.defaultHome(under: root + "/missing", environment: [:]).isEmpty)
        #expect(!FirstmateHome.isValid(""))
    }
}
