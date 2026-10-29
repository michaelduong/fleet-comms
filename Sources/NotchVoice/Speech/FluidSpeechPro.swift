//  FluidSpeechPro.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import CoreML
import FluidAudio
import Foundation

/// FluidVoice's "Fluid Speech Pro" (fluid-parakeet-pro, CC-BY-4.0): a Parakeet TDT 0.6B v3
/// fine-tune with the v3 inputs, outputs and tokenizer. It is read in place from FluidAudio's
/// shared model cache, where FluidVoice put it; this app never downloads, writes or deletes it.
enum FluidSpeechPro {
    static let directory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("FluidAudio/Models/fluid-parakeet-pro-coreml", isDirectory: true)
    }()

    static let vocabularyFile = "parakeet_vocab.json"
    static let components = ["Preprocessor", "Encoder", "Decoder", "JointDecision"]

    static var isInstalled: Bool {
        let names = components.map { $0 + ".mlmodelc" } + [vocabularyFile]
        return names.allSatisfy { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) }
    }

    /// FluidAudio's own local loader expects the joint as `JointDecisionv3.mlmodelc`; this
    /// folder names it `JointDecision.mlmodelc` with the same contract, so it is loaded here.
    static func load() throws -> AsrModels {
        guard isInstalled else { throw FluidSpeechProError.notInstalled }
        let configuration = AsrModels.defaultConfiguration()
        return try AsrModels(
            encoder: model("Encoder", units: configuration.computeUnits),
            preprocessor: model("Preprocessor", units: .cpuOnly),
            decoder: model("Decoder", units: configuration.computeUnits),
            joint: model("JointDecision", units: configuration.computeUnits),
            configuration: configuration,
            vocabulary: vocabulary(),
            version: .v3
        )
    }

    private static func model(_ name: String, units: MLComputeUnits) throws -> MLModel {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = units
        let url = directory.appendingPathComponent(name + ".mlmodelc")
        return try MLModel(contentsOf: url, configuration: configuration)
    }

    static func vocabulary(from data: Data? = nil) throws -> [Int: String] {
        let data = try data ?? Data(contentsOf: directory.appendingPathComponent(vocabularyFile))
        guard let entries = try JSONSerialization.jsonObject(with: data) as? [String: String] else {
            throw FluidSpeechProError.unreadableVocabulary
        }
        let pairs = entries.compactMap { key, token in Int(key).map { ($0, token) } }
        let vocabulary = Dictionary(pairs) { first, _ in first }
        // Every token id below the v3 blank id must be present for decoding.
        guard (0 ..< AsrModelVersion.v3.blankId).allSatisfy({ vocabulary[$0] != nil }) else {
            throw FluidSpeechProError.unreadableVocabulary
        }
        return vocabulary
    }
}

enum FluidSpeechProError: LocalizedError {
    case notInstalled
    case unreadableVocabulary

    var errorDescription: String? {
        switch self {
        case .notInstalled: "Fluid Speech Pro is not installed (FluidVoice downloads it)."
        case .unreadableVocabulary: "Fluid Speech Pro's vocabulary could not be read."
        }
    }
}
