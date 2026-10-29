//  ModelDownloadProofTests.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation
@testable import NotchVoice
import Testing

enum ModelDownloadProof {
    static var root: URL? {
        ProcessInfo.processInfo.environment["NOTCH_VOICE_MODEL_PROOF_ROOT"].map { URL(fileURLWithPath: $0) }
    }
}

/// Opt-in: downloads the first-run model set into `NOTCH_VOICE_MODEL_PROOF_ROOT` through the
/// Models library, the way onboarding does, and records how long each took. Needs the network.
@Suite(.serialized, .enabled(if: ModelDownloadProof.root != nil))
@MainActor
struct ModelDownloadProofTests {
    @Test func starterSetDownloadsDeletesAndDownloadsAgain() async throws {
        let root = try #require(ModelDownloadProof.root)
        ModelPins.apply()
        let library = ModelLibrary(root: root)
        var lines: [String] = []
        for model in LocalModel.starterSet + [.smartTurn] {
            let started = Date()
            library.download(model)
            try await settle(library, model)
            guard case let .installed(bytes) = library.status(model) else {
                Issue.record("\(model) ended as \(library.status(model))")
                continue
            }
            lines.append("\(model.rawValue) download_s=\(Int(Date().timeIntervalSince(started))) bytes=\(bytes)")
        }
        try library.delete(.smartTurn)
        #expect(library.status(.smartTurn) == .notInstalled)
        let again = Date()
        library.download(.smartTurn)
        try await settle(library, .smartTurn)
        lines.append("smartTurn redownload_s=\(Int(Date().timeIntervalSince(again)))")
        #expect(library.starterSetInstalled)
        try (lines.joined(separator: "\n") + "\n").write(
            to: root.appendingPathComponent("download-proof.txt"), atomically: true, encoding: .utf8
        )
    }

    private func settle(_ library: ModelLibrary, _ model: LocalModel) async throws {
        let deadline = Date().addingTimeInterval(20 * 60)
        while library.status(model).isDownloading || library.status(model) == .notInstalled, Date() < deadline {
            try await Task.sleep(for: .milliseconds(200))
        }
    }
}
