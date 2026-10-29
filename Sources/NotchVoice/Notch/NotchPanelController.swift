//  NotchPanelController.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import AppKit
import Observation
import SwiftUI

/// A borderless, non-activating panel that never steals focus from the app you are typing in.
/// The panel keeps one fixed size and the pill animates inside it, pinned to the edge its
/// placement grows from; clicks outside the pill fall through to whatever is underneath.
@MainActor
final class NotchPanelController {
    private let model: AppModel
    private let menu: StatusMenuBuilder
    private let panel: NotchPanel
    private let hostingView: PillHostingView<NotchRootView>
    private let hitArea = PillHitArea()
    private(set) var layout: PillLayout
    private var wasExpanded = false

    var window: NSWindow {
        panel
    }

    var contentFrameOnScreen: CGRect {
        CGRect(
            x: panel.frame.minX + hitArea.frame.minX,
            y: panel.frame.maxY - hitArea.frame.maxY,
            width: hitArea.frame.width, height: hitArea.frame.height
        )
    }

    private var pointerIsOverPill: Bool {
        panel.isVisible && contentFrameOnScreen.contains(NSEvent.mouseLocation)
    }

    init(model: AppModel, menu: StatusMenuBuilder) {
        self.model = model
        self.menu = menu
        layout = Self.makeLayout(model.settings.pillPlacement)
        hostingView = PillHostingView(
            rootView: NotchRootView(model: model, layout: layout, hitArea: hitArea, menu: menu),
            hitArea: hitArea
        )
        panel = NotchPanel(contentRect: layout.panelFrame)
        panel.contentView = hostingView
        // Invalidate stale transparent regions without forcing a synchronous redraw each animation tick.
        hitArea.onChange = { [weak panel] in panel?.contentView?.needsDisplay = true }
        model.pointerOverPill = { [weak self] in self?.pointerIsOverPill ?? false }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.relayout() }
        }
        followExpansion()
    }

    func show() {
        panel.setFrame(layout.panelFrame, display: true)
        updateVisibility()
    }

    private func updateVisibility() {
        if layout.placement == .bottomCenter, !model.displayState.isExpanded {
            panel.orderOut(nil)
            hitArea.frame = .zero
        } else {
            panel.orderFrontRegardless()
        }
    }

    /// Settings changed the placement: move at once, keeping whatever the pill is showing.
    func placementChanged() {
        relayout()
    }

    private func relayout() {
        let updated = Self.makeLayout(model.settings.pillPlacement)
        guard updated != layout else { return }
        layout = updated
        hostingView.rootView = NotchRootView(model: model, layout: updated, hitArea: hitArea, menu: menu)
        panel.setFrame(updated.panelFrame, display: true)
        updateVisibility()
    }

    /// A floating pill opens on the screen the owner is working on, so it is placed again each
    /// time it goes from resting to open.
    private func followExpansion() {
        withObservationTracking {
            _ = model.displayState.isExpanded
            _ = model.questionTakesKeyboard
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                let expanded = model.displayState.isExpanded
                if expanded, !wasExpanded, layout.placement.isFloating {
                    relayout()
                }
                wasExpanded = expanded
                updateKeyboard()
                updateVisibility()
                followExpansion()
            }
        }
    }

    /// Typing into a question must not leave the pill holding the keyboard once the question is gone.
    private func updateKeyboard() {
        let wanted = model.questionTakesKeyboard
        guard panel.acceptsKeyboard != wanted else { return }
        panel.acceptsKeyboard = wanted
        guard !wanted, panel.isKeyWindow else { return }
        let owner = NSWorkspace.shared.frontmostApplication
        panel.orderOut(nil)
        // Key status does not return to the owner's app on its own; activation hands it back.
        if let owner, owner != .current {
            NSApp.activate()
            owner.activate(from: .current, options: [])
        }
    }

    private static func makeLayout(_ placement: PillPlacement) -> PillLayout {
        PillLayout(placement: placement, geometry: NotchGeometry(screen: screen(for: placement)))
    }

    /// The notch is on one screen (or stood in for on the main one); a floating pill follows the
    /// pointer, which is where the owner is working when the hotkey is pressed.
    private static func screen(for placement: PillPlacement) -> NSScreen {
        let screens = NSScreen.screens
        let fallback = NSScreen.main ?? screens[0]
        guard placement.isFloating else {
            return screens.first { $0.safeAreaInsets.top > 0 } ?? fallback
        }
        let mouse = NSEvent.mouseLocation
        return screens.first { $0.frame.contains(mouse) } ?? fallback
    }
}

final class NotchPanel: NSPanel {
    /// On only while a question's controls are shown, so a click in its reply field takes the keyboard
    /// without activating the app.
    var acceptsKeyboard = false

    init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        title = "Fleet Comms"
        setAccessibilityLabel("Fleet Comms")
        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        // Both card themes use white text, so AppKit-drawn controls use their dark look.
        appearance = NSAppearance(named: .darkAqua)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        setAccessibilityIdentifier("notch.panel")
    }

    override var canBecomeKey: Bool {
        acceptsKeyboard
    }

    override var canBecomeMain: Bool {
        false
    }
}

/// The pill's current frame in the hosting view's top-left coordinates.
@MainActor
final class PillHitArea {
    var frame: CGRect = .zero {
        didSet { onChange?() }
    }

    var onChange: (() -> Void)?
}

final class PillHostingView<Content: View>: NSHostingView<Content> {
    private let hitArea: PillHitArea

    init(rootView: Content, hitArea: PillHitArea) {
        self.hitArea = hitArea
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @MainActor @preconcurrency required init(rootView: Content) {
        hitArea = PillHitArea()
        super.init(rootView: rootView)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let topLeft = CGPoint(x: local.x, y: isFlipped ? local.y : bounds.height - local.y)
        guard hitArea.frame.contains(topLeft) else { return nil }
        return super.hitTest(point)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
