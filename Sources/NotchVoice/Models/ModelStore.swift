//  ModelStore.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import FluidAudio
import Foundation

/// Disk facts and download or delete operations for the app's own models folder.
/// Downloads go through FluidAudio, which resumes partial files on the next attempt.
enum ModelStore {
    typealias Progress = @Sendable (_ fraction: Double?, _ activity: String) -> Void

    static func isInstalled(_ model: LocalModel, root: URL) -> Bool {
        let location = model.location(root: root)
        let files = FileManager.default
        guard files.fileExists(atPath: location.path) else { return false }
        return model.requiredFiles.allSatisfy { files.fileExists(atPath: location.appendingPathComponent($0).path) }
    }

    static func downloadVoice(_ voiceID: String, root: URL, progress: @escaping Progress) async throws {
        let directory = LocalModel.kokoro.location(root: root)
        guard !FileManager.default.fileExists(atPath: directory.appendingPathComponent("\(voiceID).bin").path) else {
            return
        }
        let title = VoiceChoice.all.first { $0.id == voiceID }?.title ?? voiceID
        progress(nil, "Downloading \(title)")
        try await KokoroAneResourceDownloader.ensureVoicePack(voiceID, repoDirectory: directory)
        progress(1, "Downloaded \(title)")
    }

    /// Bytes under a folder (or of a file), following nothing outside it.
    static func bytes(at url: URL) -> Int64 {
        let files = FileManager.default
        var isDirectory: ObjCBool = false
        guard files.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }
        guard isDirectory.boolValue else { return fileSize(url) }
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let walker = files.enumerator(at: url, includingPropertiesForKeys: keys) else { return 0 }
        var total: Int64 = 0
        for case let item as URL in walker {
            total += fileSize(item)
        }
        return total
    }

    private static func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values?.isRegularFile == true else { return 0 }
        return Int64(values?.fileSize ?? 0)
    }

    /// Removes the model's own folder. Refuses anything outside the models root.
    static func delete(_ model: LocalModel, root: URL) throws {
        guard !model.isExternal else { throw ModelStoreError.externalModel }
        let location = model.location(root: root).standardizedFileURL
        guard location.path.hasPrefix(root.standardizedFileURL.path + "/") else { throw ModelStoreError.outsideRoot }
        try FileManager.default.removeItem(at: location)
    }

    static func download(_ model: LocalModel, root: URL, progress: @escaping Progress) async throws {
        let handler: ProgressHandler = { update in
            let activity = switch update.phase {
            case .listing: "Checking"
            case .downloading: "Downloading"
            case .compiling: "Compiling"
            }
            progress(update.fractionCompleted, activity)
        }
        switch model {
        case .sileroVAD, .parakeetRealtime320, .parakeetRealtime160:
            guard let repo = model.repo else { return }
            try await ModelHub.download(repo, to: model.hubDirectory(root: root), progressHandler: handler)
        case .parakeetTdtV2:
            try await AsrModels.download(to: model.location(root: root), version: .v2, progressHandler: handler)
        case .kokoro:
            try await KokoroAneResourceDownloader.ensureModels(
                variant: .english, directory: model.hubDirectory(root: root), progressHandler: handler
            )
            // The small English lexicon lives in FluidAudio's shared cache, where its G2P loader reads it.
            _ = await KokoroAneResourceDownloader.ensureEnglishLexicon(directory: nil)
        case .smartTurn:
            _ = try await SmartTurnModelFile.ensureDownloaded(root: root) { progress($0, "Downloading") }
        case .fluidSpeechPro:
            throw ModelStoreError.externalModel
        }
    }
}

enum ModelStoreError: LocalizedError {
    case externalModel
    case outsideRoot

    var errorDescription: String? {
        switch self {
        case .externalModel: "Fluid Speech Pro belongs to FluidVoice and is only read from there."
        case .outsideRoot: "Refusing to delete a folder outside the models folder."
        }
    }
}
