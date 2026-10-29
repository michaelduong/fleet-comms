//  StatusMenuBuilder.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import AppKit

/// The menu-bar menu: talk, the quick toggles, Settings and quit. Everything else lives in
/// Settings. Rebuilt on every open so checkmarks always match the settings.
@MainActor
final class StatusMenuBuilder {
    private let settings: AppSettings
    private let model: AppModel
    private let settingsWindow: SettingsWindowController
    /// Menu items hold their targets weakly and AppKit can send the chosen action after
    /// `popUp` returns, so the last menu is kept alive until the next one opens.
    private var shownMenu: NSMenu?

    init(settings: AppSettings, model: AppModel, settingsWindow: SettingsWindowController) {
        self.settings = settings
        self.model = model
        self.settingsWindow = settingsWindow
    }

    /// Opens a fresh menu with its top-left corner at `origin`, in screen coordinates.
    func popUp(at origin: CGPoint) {
        let menu = makeMenu()
        shownMenu = menu
        menu.popUp(positioning: menu.items.first, at: origin, in: nil)
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "Fleet Comms")
        let settings = settings
        let talkTitle = "Talk to Firstmate (\(settings.hotkey.title))"
        menu.addItem(ActionMenuItem(talkTitle, id: "menu.talk", action: model.talkPressed))
        menu.addItem(.separator())
        menu.addItem(picker(
            "Voice Lane", id: "menu.voiceLane",
            options: VoiceLane.allCases.map { (title(of: $0), $0) }, selected: settings.voiceLane,
            enabled: { lane in
                lane.provider.map { settings.isRealtimeEnabled($0) && SubscriptionLogin.status($0) != .missing } ?? true
            },
            choose: { settings.voiceLane = $0 }
        ))
        menu.addItem(toggle("Fast Assistant", id: "menu.assistant", isOn: settings.assistantEnabled) {
            settings.assistantEnabled.toggle()
        })
        menu.addItem(toggle("Read Whole Reply", id: "menu.readWholeReply", isOn: settings.readWholeReply) {
            settings.readWholeReply.toggle()
        })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Settings…", id: "menu.settings", key: ",") { [settingsWindow] in
            settingsWindow.show()
        })
        menu.addItem(ActionMenuItem("Quit Fleet Comms", id: "menu.quit", key: "q") { NSApp.terminate(nil) })
        return menu
    }

    /// A realtime lane without a sign-in on this Mac is disabled, with the command that fixes it.
    /// An expired Grok token is routine: the Grok CLI renews it when a call starts.
    private func title(of lane: VoiceLane) -> String {
        guard let provider = lane.provider else { return lane.title }
        guard settings.isRealtimeEnabled(provider) else { return lane.title + " (enable in Settings › Realtime)" }
        switch SubscriptionLogin.status(provider) {
        case .valid: return lane.title
        case .expired where provider == .grok: return lane.title
        case .expired: return lane.title + " (sign-in expired; run \(provider.loginCommand))"
        case .missing: return lane.title + " (needs \(provider.loginCommand))"
        }
    }

    private func toggle(_ title: String, id: String, isOn: Bool, action: @escaping () -> Void) -> NSMenuItem {
        let item = ActionMenuItem(title, id: id, action: action)
        item.state = isOn ? .on : .off
        return item
    }

    private func picker<Value: Equatable>(
        _ title: String, id: String, options: [(String, Value)], selected: Value,
        enabled: (Value) -> Bool = { _ in true }, choose: @escaping (Value) -> Void
    ) -> NSMenuItem {
        let submenu = NSMenu()
        for (index, option) in options.enumerated() {
            let item = ActionMenuItem(option.0, id: "\(id).\(index)") { choose(option.1) }
            item.state = option.1 == selected ? .on : .off
            item.isEnabled = enabled(option.1)
            submenu.addItem(item)
        }
        submenu.autoenablesItems = false
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        parent.submenu = submenu
        parent.setAccessibilityIdentifier(id)
        return parent
    }
}

/// A menu item that runs a closure.
final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, id: String, key: String = "", action: @escaping () -> Void) {
        handler = action
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        target = self
        setAccessibilityIdentifier(id)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func fire() {
        handler()
    }
}
