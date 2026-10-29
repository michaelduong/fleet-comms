//  StatusMenuController.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import AppKit

/// The menu-bar icon. The menu is popped up by hand rather than attached to the item, so it
/// opens under the icon when the icon is visible and somewhere sensible when macOS has hidden it.
@MainActor
final class StatusMenuController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let builder: StatusMenuBuilder

    init(builder: StatusMenuBuilder) {
        self.builder = builder
        super.init()
        guard let button = statusItem.button else { return }
        let image = NSImage(named: "MenuBarIcon")
        image?.size = NSSize(width: 18, height: 18)
        image?.isTemplate = true
        image?.accessibilityDescription = "Fleet Comms"
        button.image = image
        button.toolTip = "Fleet Comms"
        button.setAccessibilityLabel("Fleet Comms")
        button.target = self
        button.action = #selector(clicked)
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        button.setAccessibilityIdentifier("menu.statusItem")
    }

    @objc private func clicked() {
        let origin = MenuPlacement.origin(
            itemFrame: statusItem.button?.window?.frame,
            mouse: NSEvent.mouseLocation,
            screens: NSScreen.screens.map(Self.placementScreen),
            notchScreen: NSScreen.screens.first { $0.safeAreaInsets.top > 0 }.map(Self.placementScreen)
        )
        let item = statusItem.button?.window?.frame ?? .zero
        EventLog.record("menu_opened", [
            "x": String(Int(origin.x)), "y": String(Int(origin.y)),
            "item_x": String(Int(item.minX)), "item_y": String(Int(item.minY))
        ])
        statusItem.button?.highlight(true)
        builder.popUp(at: origin)
        statusItem.button?.highlight(false)
    }

    private static func placementScreen(_ screen: NSScreen) -> MenuPlacement.Screen {
        MenuPlacement.Screen(
            frame: screen.frame, visibleFrame: screen.visibleFrame, safeAreaTop: screen.safeAreaInsets.top
        )
    }
}
