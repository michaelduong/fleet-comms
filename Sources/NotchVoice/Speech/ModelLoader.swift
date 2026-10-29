//  ModelLoader.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import CoreML
import FluidAudio
import Foundation

/// Downloads (first run) and loads the on-device models into this app's own
/// Application Support folder, reporting progress per step.
enum ModelLoader {
    struct Progress: Sendable {
        let step: String
        let fraction: Double?
        var activity = "Loading"
    }

    typealias ProgressSink = @Sendable (Progress) -> Void

    /// `-modelsRoot <path>` on launch points every model at another folder (a developer and test aid).
    static var modelsRoot: URL {
        if let override = UserDefaults.standard.string(forKey: "modelsRoot"), !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("NotchVoice/Models", isDirectory: true)
    }

    static func loadVad(progress: @escaping ProgressSink) async throws -> VadManager {
        progress(Progress(step: "Voice detection", fraction: 0))
        // VadManager appends "Models" to the directory it is given.
        let hub = LocalModel.sileroVAD.hubDirectory(root: modelsRoot).deletingLastPathComponent()
        return try await VadManager(
            config: VadConfig(defaultThreshold: EndpointDetector.speechThreshold),
            modelDirectory: hub,
            progressHandler: forward("Voice detection", to: progress)
        )
    }

    static func loadSmartTurn(progress: @escaping ProgressSink) async throws -> SmartTurn {
        let step = "End of turn"
        progress(Progress(step: step, fraction: 0))
        let url = try await SmartTurnModelFile.ensureDownloaded { fraction in
            progress(Progress(step: step, fraction: fraction, activity: "Downloading"))
        }
        return try SmartTurn(modelURL: url)
    }

    static func loadRecognizer(
        _ choice: SpeechModelChoice,
        silenceSeconds: Double,
        progress: @escaping ProgressSink
    ) async throws -> any SpeechRecognizer {
        let step = "Speech model"
        progress(Progress(step: step, fraction: 0))
        switch choice {
        case .parakeetRealtime320, .parakeetRealtime160:
            let manager = StreamingEouAsrManager(
                chunkSize: choice == .parakeetRealtime160 ? .ms160 : .ms320,
                eouDebounceMs: Int(silenceSeconds * 1000)
            )
            try await manager.loadModels(to: modelsRoot, progressHandler: forward(step, to: progress))
            return await RealtimeParakeetRecognizer(manager: manager)
        case .fluidSpeechPro:
            let manager = AsrManager(config: .default)
            try await manager.loadModels(FluidSpeechPro.load())
            return TdtParakeetRecognizer(manager: manager)
        case .parakeetTdtV2:
            let models = try await AsrModels.downloadAndLoad(
                to: LocalModel.parakeetTdtV2.location(root: modelsRoot),
                version: .v2,
                progressHandler: forward(step, to: progress)
            )
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            return TdtParakeetRecognizer(manager: manager)
        }
    }

    private static func forward(_ step: String, to sink: @escaping ProgressSink) -> ProgressHandler {
        { update in
            let activity = switch update.phase {
            case .listing: "Checking"
            case .downloading: "Downloading"
            case .compiling: "Compiling"
            }
            sink(Progress(step: step, fraction: update.fractionCompleted, activity: activity))
        }
    }
}
