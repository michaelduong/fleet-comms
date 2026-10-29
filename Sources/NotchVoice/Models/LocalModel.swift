//  LocalModel.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import FluidAudio
import Foundation

/// Every on-device model the app can use: what it does, where its files live and where they come from.
enum LocalModel: String, CaseIterable, Identifiable, Sendable {
    case sileroVAD
    case parakeetRealtime320
    case parakeetRealtime160
    case parakeetTdtV2
    case kokoro
    case smartTurn
    case fluidSpeechPro

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .sileroVAD: "Silero VAD"
        case .parakeetRealtime320: "Parakeet Realtime (320 ms)"
        case .parakeetRealtime160: "Parakeet Realtime (160 ms)"
        case .parakeetTdtV2: "Parakeet TDT v2"
        case .kokoro: "Kokoro voice"
        case .smartTurn: "Smart Turn v3.2"
        case .fluidSpeechPro: "Fluid Speech Pro"
        }
    }

    var role: String {
        switch self {
        case .sileroVAD: "Voice detection"
        case .parakeetRealtime320, .parakeetRealtime160, .parakeetTdtV2, .fluidSpeechPro: "Speech recognition"
        case .kokoro: "Text to speech"
        case .smartTurn: "End of turn"
        }
    }

    var detail: String {
        switch self {
        case .sileroVAD: "Hears when you start and stop talking. Always needed."
        case .parakeetRealtime320: "Streaming English recognizer with an end-of-utterance head. The default."
        case .parakeetRealtime160: "The same recognizer in 160 ms chunks: lower latency, slightly less accurate."
        case .parakeetTdtV2: "Larger offline English recognizer; also the fallback when Fluid Speech Pro fails."
        case .kokoro: "Kokoro 82M, the voice that reads replies. Always needed."
        case .smartTurn: "Judges from your voice whether you have finished. Used only when End of Turn is Smart Turn."
        case .fluidSpeechPro: "FluidVoice's Parakeet v3 fine-tune, read in place from FluidVoice's folder."
        }
    }

    var license: String {
        switch self {
        case .sileroVAD: "MIT"
        case .parakeetRealtime320, .parakeetRealtime160: "NVIDIA Open Model License"
        case .parakeetTdtV2, .fluidSpeechPro: "CC-BY-4.0"
        case .kokoro: "Apache-2.0"
        case .smartTurn: "BSD-2-Clause"
        }
    }

    /// Measured on disk after a download; shown before one.
    var approximateBytes: Int64 {
        switch self {
        case .sileroVAD: 1_100_000
        case .parakeetRealtime320, .parakeetRealtime160: 224_000_000
        case .parakeetTdtV2: 465_000_000
        case .kokoro: 85_000_000
        case .smartTurn: 8_700_000
        case .fluidSpeechPro: 652_000_000
        }
    }

    /// Lives in another app's folder: shown, never downloaded, changed or deleted here.
    var isExternal: Bool {
        self == .fluidSpeechPro
    }

    /// Nothing works without these two, so they are the first-run download.
    var isRequired: Bool {
        self == .sileroVAD || self == .kokoro
    }

    /// The first-run set: the required models plus the default recognizer.
    static let starterSet: [LocalModel] = [.sileroVAD, .kokoro, .parakeetRealtime320]

    var repo: Repo? {
        switch self {
        case .sileroVAD: .vad
        case .parakeetRealtime320: .parakeetEou320
        case .parakeetRealtime160: .parakeetEou160
        case .parakeetTdtV2: .parakeetV2
        case .kokoro: .kokoroAne
        case .smartTurn, .fluidSpeechPro: nil
        }
    }

    /// Where the files come from, for the Models list.
    var source: String {
        switch self {
        case .smartTurn: "huggingface.co/pipecat-ai/smart-turn-v3, pinned revision, SHA-256 checked"
        case .fluidSpeechPro: "Installed by FluidVoice"
        default: "huggingface.co/\(repo?.remotePath ?? ""), pinned revision"
        }
    }

    /// The directory handed to FluidAudio, which appends the repo's own folder name.
    func hubDirectory(root: URL) -> URL {
        switch self {
        case .sileroVAD: root.appendingPathComponent("VAD/Models", isDirectory: true)
        case .kokoro: root.appendingPathComponent("TTS", isDirectory: true)
        default: root
        }
    }

    /// The folder (or file) that holds this model's files on this Mac.
    func location(root: URL) -> URL {
        switch self {
        case .smartTurn: SmartTurnModelFile.url(root: root)
        case .fluidSpeechPro: FluidSpeechPro.directory
        default: hubDirectory(root: root).appendingPathComponent(repo?.folderName ?? rawValue, isDirectory: true)
        }
    }

    /// Files that must be present for the model to count as installed.
    var requiredFiles: [String] {
        switch self {
        case .sileroVAD: Array(ModelNames.VAD.requiredModels)
        case .parakeetRealtime320, .parakeetRealtime160: Array(ModelNames.ParakeetEOU.requiredModels)
        case .parakeetTdtV2: Array(ModelNames.ASR.requiredModels) + [ModelNames.ASR.vocabularyFile]
        case .kokoro: Array(ModelNames.KokoroAne.requiredModels)
        case .smartTurn: []
        case .fluidSpeechPro: FluidSpeechPro.components.map { $0 + ".mlmodelc" } + [FluidSpeechPro.vocabularyFile]
        }
    }
}
