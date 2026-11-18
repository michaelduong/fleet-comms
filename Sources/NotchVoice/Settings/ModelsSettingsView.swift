//  ModelsSettingsView.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import AppKit
import SwiftUI

/// Every local model with its state on disk, and the controls to fetch or remove it.
struct ModelsSettingsView: View {
    let library: ModelLibrary
    let settings: AppSettings
    @State private var pendingDelete: LocalModel?
    @State private var deleteError: String?

    var body: some View {
        Form {
            Section {
                ForEach(LocalModel.allCases) { model in
                    ModelRow(model: model, library: library, inUse: model.isInUse(settings: settings)) {
                        pendingDelete = model
                    }
                }
            } header: {
                Text("On this Mac")
            } footer: {
                footer
            }
        }
        .formStyle(.grouped)
        .onAppear { library.refresh() }
        .alert("Delete \(pendingDelete?.title ?? "")?", isPresented: deleteShown, presenting: pendingDelete) { model in
            Button("Delete", role: .destructive) { delete(model) }
                .accessibilityIdentifier("settings.models.confirmDelete")
            Button("Cancel", role: .cancel) {}
        } message: { model in
            Text("Removes \(ByteCount.string(bytesOf(model))) from the models folder. It downloads again when needed.")
        }
        .alert("Could not delete", isPresented: errorShown) {
            Button("OK") { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
        .accessibilityIdentifier("settings.models")
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Disk use: \(ByteCount.string(library.installedBytes)) in \(library.root.path.abbreviatingHome)")
                .accessibilityIdentifier("settings.models.diskUse")
            HStack {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([library.root])
                }
                .accessibilityIdentifier("settings.models.showInFinder")
                Button("Refresh") { library.refresh() }
                    .accessibilityIdentifier("settings.models.refresh")
            }
            Text("Downloads are pinned to one revision of each source and resume where they stopped. "
                + "Fluid Speech Pro is only ever read from FluidVoice's folder.")
                .accessibilityIdentifier("settings.models.note")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    private var deleteShown: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private var errorShown: Binding<Bool> {
        Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })
    }

    private func bytesOf(_ model: LocalModel) -> Int64 {
        if case let .installed(bytes) = library.status(model) {
            return bytes
        }
        return 0
    }

    private func delete(_ model: LocalModel) {
        do {
            try library.delete(model)
        } catch {
            deleteError = error.localizedDescription
        }
    }
}

struct ModelRow: View {
    let model: LocalModel
    let library: ModelLibrary
    let inUse: Bool
    /// Onboarding shows the short form: no licence and source line.
    var compact = false
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.title)
                        .font(.body.weight(.medium))
                        .accessibilityIdentifier("settings.models.\(model.rawValue).title")
                    Text(compact ? model.role : "\(model.role) · \(model.detail)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !compact {
                        Text("\(model.license) · \(model.source)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .accessibilityIdentifier("settings.models.\(model.rawValue).source")
                    }
                }
                Spacer(minLength: 12)
                actions
            }
            if case let .downloading(fraction, activity) = library.status(model) {
                ProgressView(value: fraction ?? 0)
                    .accessibilityIdentifier("settings.models.\(model.rawValue).progress")
                Text(fraction.map { "\(activity) · \(Int($0 * 100))%" } ?? activity)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.models.\(model.rawValue)")
    }

    @ViewBuilder
    private var actions: some View {
        let id = "settings.models.\(model.rawValue)"
        switch library.status(model) {
        case .notInstalled:
            HStack {
                Text("About \(ByteCount.string(model.approximateBytes))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Download") { library.download(model) }
                    .accessibilityIdentifier(id + ".download")
            }
        case .downloading:
            Button("Cancel") { library.cancel(model) }
                .accessibilityIdentifier(id + ".cancel")
        case let .installed(bytes):
            HStack {
                StatusText(tone: .ready, text: ByteCount.string(bytes), identifier: id + ".status")
                Button(inUse ? "In use" : "Delete", action: onDelete)
                    .disabled(inUse)
                    .help(inUse ? "Chosen in settings right now, so it stays." : "Remove its files from this Mac.")
                    .accessibilityIdentifier(id + ".delete")
            }
        case let .failed(message):
            HStack {
                StatusText(tone: .missing, text: message, identifier: id + ".status")
                    .lineLimit(2)
                Button("Retry") { library.download(model) }
                    .accessibilityIdentifier(id + ".download")
            }
        case let .external(found, bytes):
            StatusText(
                tone: found ? .ready : .neutral,
                text: found
                    ? "Found in FluidVoice · \(ByteCount.string(bytes))"
                    : "Not installed; FluidVoice downloads it.",
                identifier: id + ".status"
            )
        }
    }
}

extension LocalModel {
    /// Chosen by the current settings, so it may not be deleted while that holds.
    @MainActor func isInUse(settings: AppSettings) -> Bool {
        switch self {
        case .sileroVAD, .kokoro: true
        case .parakeetRealtime320: settings.speechModel == .parakeetRealtime320
        case .parakeetRealtime160: settings.speechModel == .parakeetRealtime160
        case .parakeetTdtV2: settings.speechModel == .parakeetTdtV2 || settings.speechModel == .fluidSpeechPro
        case .smartTurn: settings.endOfTurn == .smartTurn
        case .fluidSpeechPro: settings.speechModel == .fluidSpeechPro
        }
    }
}
