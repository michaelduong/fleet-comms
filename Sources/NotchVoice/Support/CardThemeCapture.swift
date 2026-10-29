//  CardThemeCapture.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import AppKit
import ScreenCaptureKit
import SwiftUI

/// Opt-in compositor screenshots: layer rendering cannot prove a translucent window material.
@MainActor
enum CardThemeCapture {
    static func startIfRequested(model: AppModel, settingsWindow: SettingsWindowController) -> Bool {
        guard let path = DeveloperActions.argument("--capture-card-themes") else { return false }
        let menu = StatusMenuBuilder(settings: model.settings, model: model, settingsWindow: settingsWindow)
        let pill = NotchPanelController(model: model, menu: menu)
        model.settings.onChange = { change in
            if case .placement = change {
                pill.placementChanged()
            }
        }
        Task {
            do {
                try await capture(to: URL(fileURLWithPath: path), pill: pill, model: model)
                try await captureSettings(to: URL(fileURLWithPath: path), model: model)
            } catch {
                try? String(describing: error).write(
                    to: URL(fileURLWithPath: path).appendingPathComponent("capture-error.txt"),
                    atomically: true, encoding: .utf8
                )
            }
            NSApp.terminate(nil)
        }
        return true
    }

    private static func capture(to folder: URL, pill: NotchPanelController, model: AppModel) async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let backdrop = NSWindow(
            contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false
        )
        backdrop.isReleasedWhenClosed = false
        backdrop.level = .statusBar
        backdrop.isOpaque = true
        backdrop.ignoresMouseEvents = true
        defer { backdrop.orderOut(nil); pill.window.orderOut(nil) }
        for dark in [false, true] {
            backdrop.contentView = NSHostingView(rootView: ProofBackdrop(dark: dark))
            for theme in CardTheme.allCases {
                model.settings.cardTheme = theme
                for placement in PillPlacement.allCases {
                    model.settings.pillPlacement = placement
                    model.state = .reply(
                        text: "The build is green. The update is ready for review. "
                            + "All three placements keep the reply and its controls readable.",
                        speaking: false, from: .firstMate
                    )
                    pill.show()
                    backdrop.setFrame(pill.layout.geometry.screenFrame, display: true)
                    backdrop.order(.below, relativeTo: pill.window.windowNumber)
                    try await Task.sleep(for: .seconds(1))
                    let name = "\(theme.rawValue)-\(placement.rawValue)-\(dark ? "dark" : "light").png"
                    let frame = pill.contentFrameOnScreen.insetBy(dx: -20, dy: -20)
                        .intersection(pill.layout.geometry.screenFrame)
                    try await screenshot(
                        frame,
                        windows: [pill.window, backdrop],
                        to: folder.appendingPathComponent(name)
                    )
                }
            }
        }
    }

    private static func captureSettings(to folder: URL, model: AppModel) async throws {
        model.settings.firstmateHome = ""
        // The real General form, with discovery disabled so proof never enumerates installed homes.
        let view = GeneralSettingsView(settings: model.settings, launchAtLogin: LaunchAtLogin(), homeCandidates: [])
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "General – Fleet Comms"
        window.setContentSize(NSSize(width: 600, height: 680))
        window.isReleasedWhenClosed = false
        window.center()
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        for dark in [false, true] {
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            try await Task.sleep(for: .seconds(1))
            UICapture.write(
                window,
                to: folder.appendingPathComponent("settings-general-\(dark ? "dark" : "light").png")
            )
        }
    }

    private static func screenshot(_ frame: CGRect, windows: [NSWindow], to file: URL) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let ids = Set(windows.map { CGWindowID($0.windowNumber) })
        let included = content.windows.filter { ids.contains($0.windowID) }
        guard let screen = windows.first?.screen,
              let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let display = content.displays.first(where: { $0.displayID == id }),
              included.count == windows.count else {
            throw CocoaError(.fileReadUnknown)
        }
        // Including only these two windows excludes menus and panels from concurrent proof sessions.
        let filter = SCContentFilter(display: display, including: included)
        let config = SCStreamConfiguration()
        config.sourceRect = CGRect(
            x: frame.minX - screen.frame.minX, y: screen.frame.maxY - frame.maxY,
            width: frame.width, height: frame.height
        )
        config.width = Int(frame.width * screen.backingScaleFactor)
        config.height = Int(frame.height * screen.backingScaleFactor)
        config.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: file)
    }

    private struct ProofBackdrop: View {
        let dark: Bool

        var body: some View {
            ZStack {
                Color(white: dark ? 0.08 : 0.95)
                HStack(spacing: 0) {
                    Color(white: dark ? 0.18 : 0.8)
                    Color.cyan.opacity(dark ? 0.15 : 0.2)
                    Color.clear
                }
                .rotationEffect(.degrees(-25))
                .scaleEffect(2)
            }
            .accessibilityHidden(true)
        }
    }
}
