//  LocalModelTests.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import FluidAudio
import Foundation
@testable import NotchVoice
import Testing

struct LocalModelTests {
    @Test func speechModelLicensesMatchTheirNotices() {
        #expect(LocalModel.parakeetRealtime320.license == "NVIDIA Open Model License")
        #expect(LocalModel.parakeetRealtime160.license == "NVIDIA Open Model License")
        #expect(LocalModel.parakeetTdtV2.license == "CC-BY-4.0")
        #expect(LocalModel.fluidSpeechPro.license == "CC-BY-4.0")
    }

    private func makeRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("models-\(UUID().uuidString)", isDirectory: true)
    }

    /// Writes the files a model needs, each `bytes` long, where the app would look for them.
    private func install(_ model: LocalModel, root: URL, bytes: Int = 1000) throws {
        let location = model.location(root: root)
        let files = model.requiredFiles.isEmpty ? [""] : model.requiredFiles
        for file in files {
            let url = file.isEmpty ? location : location.appendingPathComponent(file)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try Data(repeating: 1, count: bytes).write(to: url)
        }
    }

    @Test func everyManagedModelLivesUnderTheRootAndMatchesTheLoaders() {
        let root = URL(fileURLWithPath: "/tmp/root")
        for model in LocalModel.allCases where !model.isExternal {
            #expect(model.location(root: root).path.hasPrefix("/tmp/root/"), "\(model)")
        }
        #expect(LocalModel.sileroVAD.location(root: root).path == "/tmp/root/VAD/Models/" + Repo.vad.folderName)
        #expect(LocalModel.parakeetRealtime320.location(root: root).path == "/tmp/root/parakeet-eou-streaming/320ms")
        #expect(LocalModel.parakeetTdtV2.location(root: root).path == "/tmp/root/" + Repo.parakeetV2.folderName)
        #expect(LocalModel.kokoro.location(root: root).path == "/tmp/root/TTS/kokoro-82m-coreml/ANE")
        #expect(LocalModel.smartTurn.location(root: root).path == "/tmp/root/SmartTurn/" + SmartTurnModelFile.name)
        #expect(LocalModel.fluidSpeechPro.location(root: root) == FluidSpeechPro.directory)
    }

    @Test func installedStatusNeedsEveryRequiredFile() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(!ModelStore.isInstalled(.parakeetTdtV2, root: root))
        try install(.parakeetTdtV2, root: root, bytes: 2048)
        #expect(ModelStore.isInstalled(.parakeetTdtV2, root: root))
        let location = LocalModel.parakeetTdtV2.location(root: root)
        #expect(ModelStore.bytes(at: location) == Int64(2048 * LocalModel.parakeetTdtV2.requiredFiles.count))
        try FileManager.default.removeItem(at: location.appendingPathComponent(ModelNames.ASR.vocabularyFile))
        #expect(!ModelStore.isInstalled(.parakeetTdtV2, root: root))
        try install(.smartTurn, root: root, bytes: 10)
        #expect(ModelStore.isInstalled(.smartTurn, root: root))
        #expect(ModelStore.bytes(at: LocalModel.smartTurn.location(root: root)) == 10)
    }

    @Test func deleteStaysInsideTheRootAndNeverTouchesFluidVoice() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try install(.parakeetRealtime160, root: root)
        try install(.parakeetRealtime320, root: root)
        try ModelStore.delete(.parakeetRealtime160, root: root)
        #expect(!ModelStore.isInstalled(.parakeetRealtime160, root: root))
        #expect(ModelStore.isInstalled(.parakeetRealtime320, root: root))
        #expect(throws: ModelStoreError.self) { try ModelStore.delete(.fluidSpeechPro, root: root) }
        #expect(throws: (any Error).self) { try ModelStore.delete(.kokoro, root: root) }
        #expect(FileManager.default.fileExists(atPath: root.path))
    }

    @Test func everyHubRepoIsPinnedToARevision() {
        for model in LocalModel.allCases where model.repo != nil {
            let revision = ModelPins.revision(for: model)
            #expect(revision?.count == 40, "\(model) should pin a full commit hash")
        }
        #expect(ModelPins.revision(for: .smartTurn) == nil)
        #expect(LocalModel.starterSet.allSatisfy { !$0.isExternal })
    }

    @Test @MainActor func inUseFollowsTheSettingsAndLibraryTracksDisk() async throws {
        let name = "NotchVoice.models.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults)
        settings.speechModel = .parakeetTdtV2
        settings.endOfTurn = .silence
        #expect(LocalModel.sileroVAD.isInUse(settings: settings))
        #expect(LocalModel.parakeetTdtV2.isInUse(settings: settings))
        #expect(!LocalModel.parakeetRealtime320.isInUse(settings: settings))
        #expect(!LocalModel.smartTurn.isInUse(settings: settings))

        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try install(.smartTurn, root: root, bytes: 50)
        let library = ModelLibrary(root: root)
        #expect(library.status(.smartTurn) == .notInstalled)
        library.refresh()
        let deadline = Date().addingTimeInterval(5)
        while library.status(.smartTurn) == .notInstalled, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(library.status(.smartTurn) == .installed(bytes: 50))
        #expect(library.installedBytes == 50)
        try library.delete(.smartTurn)
        #expect(library.status(.smartTurn) == .notInstalled)
        #expect(!FileManager.default.fileExists(atPath: LocalModel.smartTurn.location(root: root).path))
    }
}
