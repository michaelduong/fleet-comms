//  DeveloperActions.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import AppKit
import UniformTypeIdentifiers

/// Developer tools, all opt-in: feed a recording through the real listening pipeline instead
/// of the mic, force an appearance, or render the windows to files. See CONTRIBUTING.md.
@MainActor
final class DeveloperActions {
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    func chooseWav() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.wav, .audio]
        panel.allowsMultipleSelection = false
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        feed(url)
    }

    /// Notes sent this way start with "TEST notch-voice:" so they are recognisable.
    func feed(_ url: URL) {
        model.speaker.stop()
        model.startTalking(.wav(url), notePrefix: AppModel.testNotePrefix)
    }

    /// `--feed-wav <path>` on launch feeds that file once the models are ready.
    func feedLaunchArgumentWhenReady() {
        guard let path = Self.argument("--feed-wav") else { return }
        let url = URL(fileURLWithPath: path)
        Task {
            while model.isLoading || !model.modelsReady || !model.speaker.isLoaded {
                try? await Task.sleep(for: .milliseconds(250))
            }
            feed(url)
        }
    }

    /// `--appearance light|dark` forces the app's appearance, to check the UI in both
    /// without changing the system setting.
    func applyAppearanceArgument() {
        guard let name = Self.argument("--appearance") else { return }
        NSApp.appearance = NSAppearance(named: name == "light" ? .aqua : .darkAqua)
    }

    func revealEventLog() {
        NSWorkspace.shared.activateFileViewerSelecting([EventLog.url])
    }

    /// `--capture-ui <folder>` writes every Settings section, onboarding step and pill placement
    /// as PNGs, then quits.
    func captureIfRequested(
        settings: SettingsWindowController, onboarding: () -> OnboardingWindowController, pill: NotchPanelController
    ) {
        guard let folder = Self.argument("--capture-ui") else { return }
        let onboarding = onboarding()
        Task {
            await UICapture.captureAll(
                to: URL(fileURLWithPath: folder, isDirectory: true), settings: settings, onboarding: onboarding,
                pill: pill, model: model
            )
            NSApp.terminate(nil)
        }
    }

    static func argument(_ flag: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
        return args[index + 1]
    }
}
