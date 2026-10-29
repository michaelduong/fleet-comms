//  OnboardingWindowController.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import AppKit
import SwiftUI

/// The first-run window. Closing it counts as finishing, so it never nags.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    let flow = OnboardingFlow()
    private(set) var window: NSWindow?
    private let dependencies: OnboardingDependencies
    private let onFinish: () -> Void

    init(dependencies: OnboardingDependencies, onFinish: @escaping () -> Void) {
        self.dependencies = dependencies
        self.onFinish = onFinish
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func finish() {
        window?.delegate = nil
        window?.close()
        window = nil
        onFinish()
    }

    func windowWillClose(_ notification: Notification) {
        window?.delegate = nil
        window = nil
        onFinish()
    }

    private func makeWindow() -> NSWindow {
        let root = OnboardingView(dependencies: dependencies, flow: flow)
        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.title = "Welcome to Fleet Comms"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setAccessibilityIdentifier("onboarding.window")
        return window
    }
}
