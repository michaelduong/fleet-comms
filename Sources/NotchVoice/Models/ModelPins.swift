//  ModelPins.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import FluidAudio
import Foundation

/// The Hugging Face revisions this build downloads, so a push to a model repo cannot change
/// the files a release loads. Recorded 10/28/26; bump them together with the FluidAudio version.
enum ModelPins {
    static let revisions: [String: String] = [
        "FluidInference/silero-vad-coreml": "b419383c55c110e2c9271fa6ee0ea83d03c70d96",
        "FluidInference/parakeet-realtime-eou-120m-coreml": "40a23f4c0b333aa17ad8c0f2ea47ec2347f2f355",
        "FluidInference/parakeet-tdt-0.6b-v2-coreml": "ee09c569f73759e6d44c9bd16766f477b2b36d39",
        "FluidInference/kokoro-82m-coreml": "e61d9ee79a01ad4ebf6b3d8bcfe2a03f6b8da105"
    ]

    /// Models downloaded before pinning are adopted in place once their files match the pinned
    /// listing (FluidAudio verifies the hashes and writes a revision marker); nothing is refetched.
    static func apply() {
        ModelRegistry.revisionOverrides = revisions
    }

    static func revision(for model: LocalModel) -> String? {
        guard let repo = model.repo else { return nil }
        return revisions.first { repo.remotePath == $0.key || repo.remotePath.hasPrefix($0.key + "/") }?.value
    }
}
