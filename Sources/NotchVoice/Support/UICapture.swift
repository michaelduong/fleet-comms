//  UICapture.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import AppKit

/// Renders windows to PNG files for PR proof without screen-recording permission: the
/// window's layer tree is drawn into a bitmap, so window materials come out flat.
@MainActor
enum UICapture {
    static func captureAll(
        to folder: URL, settings: SettingsWindowController, onboarding: OnboardingWindowController,
        pill: NotchPanelController, model: AppModel
    ) async {
        let suffix = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? "dark" : "light"
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if DeveloperActions.argument("--capture-thinking") != nil {
            await captureThinking(to: folder, pill: pill, model: model, suffix: suffix)
            return
        }
        settings.show()
        for section in SettingsSection.allCases {
            settings.navigation.section = section
            await settle()
            if let window = settings.window {
                write(window, to: folder.appendingPathComponent("settings-\(section.rawValue)-\(suffix).png"))
            }
        }
        settings.window?.orderOut(nil)
        onboarding.show()
        for step in OnboardingStep.allCases {
            onboarding.flow.step = step
            await settle()
            if let window = onboarding.window {
                write(window, to: folder.appendingPathComponent("onboarding-\(step.rawValue)-\(suffix).png"))
            }
        }
        onboarding.window?.orderOut(nil)
        await capturePlacements(to: folder, pill: pill, model: model, suffix: suffix)
    }

    private static func captureThinking(
        to folder: URL, pill: NotchPanelController, model: AppModel, suffix: String
    ) async {
        let requested = DeveloperActions.argument("--capture-thinking-placement")
        for placement in PillPlacement.allCases where requested == nil || requested == placement.rawValue {
            model.settings.pillPlacement = placement
            pill.placementChanged()
            let backdrop = recordingBackdrop(frame: pill.layout.panelFrame)
            pill.window.level = NSWindow.Level(rawValue: backdrop.level.rawValue + 1)
            pill.window.orderFrontRegardless()
            defer { backdrop.orderOut(nil) }
            let frame = pill.layout.panelFrame
            let top = NSScreen.screens[0].frame.maxY - frame.maxY
            let rect = "\(Int(frame.minX)),\(Int(top)),\(Int(frame.width)),\(Int(frame.height))"
            try? rect.write(to: folder.appendingPathComponent("recording-rect.txt"), atomically: true, encoding: .utf8)
            let prefix = "\(placement.rawValue)-\(suffix)"
            model.state = .reply(text: sampleReply, speaking: false, from: .assistant)
            await settle()
            model.state = .waiting
            await settle()
            write(pill.window, to: folder.appendingPathComponent("\(prefix)-waiting.png"))
            model.state = .thinking
            await settle()
            write(pill.window, to: folder.appendingPathComponent("\(prefix)-thinking.png"))
            model.state = .reply(text: sampleReply, speaking: false, from: .assistant)
            try? await Task.sleep(for: .seconds(2))
            write(pill.window, to: folder.appendingPathComponent("\(prefix)-reply.png"))
            try? await Task.sleep(for: .seconds(3))
        }
    }

    private static func recordingBackdrop(frame: CGRect) -> NSWindow {
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.backgroundColor = NSColor(white: 0.18, alpha: 1)
        window.isOpaque = true
        window.hasShadow = false
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        window.ignoresMouseEvents = true
        window.orderFrontRegardless()
        return window
    }

    /// The pill at rest, listening and showing a reply, in every placement, drawn over a plain
    /// screen-sized backdrop so the position on screen is visible.
    private static func capturePlacements(
        to folder: URL, pill: NotchPanelController, model: AppModel, suffix: String
    ) async {
        let settings = model.settings
        let placement = settings.pillPlacement
        let pendingReplies = model.pendingReplies
        if let count = DeveloperActions.argument("--pending-replies").flatMap(Int.init) {
            model.pendingReplies = max(0, count)
        }
        for candidate in PillPlacement.allCases {
            settings.pillPlacement = candidate
            for (name, state) in sampleStates {
                model.transcript = sampleTranscript
                model.level = 0.6
                model.state = state
                await settle()
                let file = folder.appendingPathComponent("pill-\(candidate.rawValue)-\(name)-\(suffix).png")
                if let rendered = render(pill.window),
                   let screen = backdrop(rendered, layout: pill.layout, dark: suffix == "dark"),
                   let data = screen.representation(using: .png, properties: [:]) {
                    try? data.write(to: file)
                }
            }
        }
        model.state = .idle
        model.transcript = ""
        model.pendingReplies = pendingReplies
        settings.pillPlacement = placement
    }

    private static var sampleStates: [(String, NotchState)] {
        if let path = DeveloperActions.argument("--capture-reply-text"),
           let text = try? String(contentsOfFile: path, encoding: .utf8) {
            return [
                ("reply-speaking", .reply(text: text, speaking: true, from: .firstMate)),
                ("reply", .reply(text: text, speaking: false, from: .firstMate))
            ]
        }
        return [
            ("idle", .idle),
            ("listening", .listening),
            ("reply", .reply(text: sampleReply, speaking: false, from: .firstMate))
        ]
    }

    private static let sampleTranscript = "Is the build green, and what is left on the review?"
    private static let sampleReply = "The build is green. Two review notes are left: a naming nit and a "
        + "missing test for the empty state. I will have both done in about ten minutes."

    /// Long enough for SwiftUI to lay out and draw the new content.
    private static func settle() async {
        try? await Task.sleep(for: .milliseconds(700))
    }

    static func write(_ window: NSWindow, to url: URL) {
        guard let bitmap = render(window), let data = bitmap.representation(using: .png, properties: [:]) else {
            return
        }
        try? data.write(to: url)
    }

    static func render(_ window: NSWindow) -> NSBitmapImageRep? {
        // The content view's superview is the frame view: title bar, toolbar and content.
        guard let frameView = window.contentView?.superview, let layer = frameView.layer else { return nil }
        let scale = window.backingScaleFactor
        let size = frameView.bounds.size
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        bitmap.size = size
        let graphics = context.cgContext
        graphics.scaleBy(x: scale, y: scale)
        // A fresh bitmap is not blank; a transparent panel would otherwise sit on leftover pixels.
        graphics.clear(CGRect(origin: .zero, size: size))
        layer.render(in: graphics)
        return bitmap
    }

    /// The panel drawn where it sits on its screen; the Dock and menu bar areas are a shade apart.
    private static func backdrop(_ panel: NSBitmapImageRep, layout: PillLayout, dark: Bool) -> NSBitmapImageRep? {
        let screen = layout.geometry.screenFrame
        let scale: CGFloat = 2
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(screen.width * scale), pixelsHigh: Int(screen.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap), let image = panel.cgImage else { return nil }
        bitmap.size = screen.size
        let graphics = context.cgContext
        graphics.scaleBy(x: scale, y: scale)
        graphics.setFillColor(gray: dark ? 0.1 : 0.78, alpha: 1)
        graphics.fill(CGRect(origin: .zero, size: screen.size))
        graphics.setFillColor(gray: dark ? 0.17 : 0.9, alpha: 1)
        graphics.fill(layout.geometry.visibleFrame.offsetBy(dx: -screen.minX, dy: -screen.minY))
        graphics.draw(image, in: layout.panelFrame.offsetBy(dx: -screen.minX, dy: -screen.minY))
        return bitmap
    }
}
