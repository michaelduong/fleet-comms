//  ModelLibrary.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation
import Observation

/// What is on disk for each model, and the downloads in flight, for the Models settings and onboarding.
@MainActor
@Observable
final class ModelLibrary {
    enum Status: Equatable {
        case notInstalled
        case downloading(fraction: Double?, activity: String)
        case installed(bytes: Int64)
        case failed(String)
        /// Fluid Speech Pro: present in FluidVoice's folder or not.
        case external(found: Bool, bytes: Int64)

        var isInstalled: Bool {
            switch self {
            case .installed, .external(found: true, _): true
            default: false
            }
        }

        var isDownloading: Bool {
            if case .downloading = self {
                return true
            }
            return false
        }
    }

    let root: URL
    private(set) var statuses: [LocalModel: Status] = [:]
    @ObservationIgnored private var tasks: [LocalModel: Task<Void, Never>] = [:]
    /// Called after a download lands, so loaded models can be refreshed.
    @ObservationIgnored var onInstalled: ((LocalModel) -> Void)?

    init(root: URL = ModelLoader.modelsRoot) {
        self.root = root
        for model in LocalModel.allCases {
            statuses[model] = model.isExternal ? .external(found: false, bytes: 0) : .notInstalled
        }
    }

    func status(_ model: LocalModel) -> Status {
        statuses[model] ?? .notInstalled
    }

    var installedBytes: Int64 {
        statuses.values.reduce(0) { total, status in
            if case let .installed(bytes) = status {
                return total + bytes
            }
            return total
        }
    }

    var starterSetInstalled: Bool {
        LocalModel.starterSet.allSatisfy { status($0).isInstalled }
    }

    var hasActiveDownloads: Bool {
        !tasks.isEmpty
    }

    /// Re-reads disk off the main thread; downloads in flight keep their status.
    func refresh() {
        let root = root
        Task.detached(priority: .utility) {
            var found: [LocalModel: Status] = [:]
            for model in LocalModel.allCases {
                let installed = ModelStore.isInstalled(model, root: root)
                let bytes = installed ? ModelStore.bytes(at: model.location(root: root)) : 0
                found[model] = model.isExternal
                    ? .external(found: installed, bytes: bytes)
                    : (installed ? .installed(bytes: bytes) : .notInstalled)
            }
            let snapshot = found
            await MainActor.run { self.apply(snapshot) }
        }
    }

    private func apply(_ found: [LocalModel: Status]) {
        for (model, status) in found where tasks[model] == nil {
            statuses[model] = status
        }
    }

    func download(_ model: LocalModel) {
        guard !model.isExternal, tasks[model] == nil else { return }
        statuses[model] = .downloading(fraction: 0, activity: "Starting")
        let root = root
        EventLog.record("model_download_started", ["model": model.rawValue])
        let started = Date()
        tasks[model] = Task {
            do {
                try await ModelStore.download(model, root: root) { fraction, activity in
                    Task { @MainActor in self.progressed(model, fraction: fraction, activity: activity) }
                }
                let bytes = ModelStore.bytes(at: model.location(root: root))
                statuses[model] = .installed(bytes: bytes)
                EventLog.record("model_download_finished", [
                    "model": model.rawValue, "ms": EventLog.milliseconds(from: started), "bytes": String(bytes)
                ])
                onInstalled?(model)
            } catch is CancellationError {
                statuses[model] = .notInstalled
            } catch {
                EventLog.record("model_download_failed", ["model": model.rawValue])
                statuses[model] = .failed(error.localizedDescription)
            }
            tasks[model] = nil
            refresh()
        }
    }

    private func progressed(_ model: LocalModel, fraction: Double?, activity: String) {
        guard tasks[model] != nil else { return }
        statuses[model] = .downloading(fraction: fraction, activity: activity)
    }

    /// Stops a download; the bytes already on disk are reused by the next attempt.
    func cancel(_ model: LocalModel) {
        tasks[model]?.cancel()
    }

    func delete(_ model: LocalModel) throws {
        try ModelStore.delete(model, root: root)
        statuses[model] = .notInstalled
        EventLog.record("model_deleted", ["model": model.rawValue])
    }

    func downloadStarterSet() {
        for model in LocalModel.starterSet where !status(model).isInstalled {
            download(model)
        }
    }
}
