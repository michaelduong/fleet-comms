//  NotchVoiceApp.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import SwiftUI

@main
struct NotchVoiceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    /// The menu-bar icon and the windows are AppKit (StatusMenuController); SwiftUI's
    /// MenuBarExtra anchors its menu to the icon even when macOS has hidden the icon off screen.
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()
    let launchAtLogin = LaunchAtLogin()
    let library = ModelLibrary()
    let microphone = MicrophonePermission()
    lazy var model = AppModel(settings: settings)
    lazy var developer = DeveloperActions(model: model)
    let updater = AppUpdater()
    lazy var settingsWindow = SettingsWindowController(dependencies: settingsDependencies, updater: updater)
    private var settingsDependencies: SettingsDependencies {
        SettingsDependencies(
            settings: settings, model: model, library: library, launchAtLogin: launchAtLogin, developer: developer,
            showOnboarding: { [weak self] in self?.showOnboarding() }
        )
    }

    private var panel: NotchPanelController?
    private var hotkeys: HotkeyCenter?
    private var statusMenu: StatusMenuController?
    private var onboarding: OnboardingWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // As the unit-test host, stay inert: no hotkey, panel or model download.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        #if DEBUG
            if AskQuestionProof.startIfRequested(model: model, settingsWindow: settingsWindow) {
                return
            }
            if AboutCapture.startIfRequested(dependencies: settingsDependencies) {
                return
            }
        #endif
        updater.start()
        ModelPins.apply()
        developer.applyAppearanceArgument()
        let model = model
        if CardThemeCapture.startIfRequested(model: model, settingsWindow: settingsWindow) {
            return
        }
        let hotkeys = HotkeyCenter(onTalk: { model.talkPressed() }, onEscape: { model.escapePressed() })
        hotkeys.registerTalk(settings.hotkey)
        model.hotkeys = hotkeys
        self.hotkeys = hotkeys

        settings.onChange = { [weak self] change in self?.settingChanged(change) }
        library.onInstalled = { [weak self] _ in self?.prepareModelsWhenIdle() }

        let menu = StatusMenuBuilder(settings: settings, model: model, settingsWindow: settingsWindow)
        statusMenu = StatusMenuController(builder: menu)

        let panel = NotchPanelController(model: model, menu: menu)
        panel.show()
        self.panel = panel
        model.startQuestions()

        if settings.onboardingCompleted {
            model.prepareModels()
        } else {
            showOnboarding()
        }
        model.configureAssistant()
        model.configureAutoSpeak()
        developer.feedLaunchArgumentWhenReady()
        developer.captureIfRequested(settings: settingsWindow, onboarding: makeOnboarding, pill: panel)
    }

    /// Loading would download missing models itself, so it waits for the Models list and onboarding.
    private func prepareModelsWhenIdle() {
        guard onboarding == nil, !library.hasActiveDownloads else { return }
        model.prepareModels()
    }

    private func showOnboarding() {
        let controller = onboarding ?? makeOnboarding()
        onboarding = controller
        controller.show()
    }

    private func makeOnboarding() -> OnboardingWindowController {
        let dependencies = OnboardingDependencies(
            settings: settings, library: library, microphone: microphone,
            openSettings: { [weak self] section in self?.settingsWindow.show(section) },
            finish: { [weak self] in self?.onboarding?.finish() }
        )
        return OnboardingWindowController(dependencies: dependencies) { [weak self] in
            guard let self else { return }
            onboarding = nil
            settings.onboardingCompleted = true
            prepareModelsWhenIdle()
        }
    }

    private func settingChanged(_ change: AppSettings.Change) {
        switch change {
        case .autoSpeak: model.configureAutoSpeak()
        case .speechModel: prepareModelsWhenIdle()
        case .voice: model.voiceChanged()
        case .hotkey: hotkeys?.registerTalk(settings.hotkey)
        case .placement: panel?.placementChanged()
        case .assistant, .fleetSchedule, .refreshFleet:
            assistantSettingChanged(change)
        case .voiceLane:
            model.endCallQuietly()
            if model.state.isCall {
                model.state = .idle
            }
            model.configureAssistant()
        case .followUp:
            if model.isFollowUp, !settings.keepListeningAfterReply {
                model.cancelListening()
            }
        }
    }

    private func assistantSettingChanged(_ change: AppSettings.Change) {
        switch change {
        case .assistant:
            model.configureAssistant()
            model.startQuestions()
        case .fleetSchedule: model.configureFleetSchedule()
        case .refreshFleet: model.fleet.refreshManually()
        default: break
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stopQuestions()
    }
}
