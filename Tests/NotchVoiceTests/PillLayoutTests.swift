//  PillLayoutTests.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import AppKit
import CoreGraphics
import Foundation
@testable import NotchVoice
import SwiftUI
import Testing

struct PillLayoutTests {
    /// A notched built-in display with the menu bar and a Dock at the bottom.
    private let notched = NotchGeometry(
        hasNotch: true, notchWidth: 200, topBarHeight: 38,
        screenFrame: CGRect(x: 0, y: 0, width: 1800, height: 1169),
        visibleFrame: CGRect(x: 0, y: 80, width: 1800, height: 1051)
    )

    /// A second display to the right, without a notch and with its own menu bar.
    private let external = NotchGeometry(
        hasNotch: false, notchWidth: 160, topBarHeight: 24,
        screenFrame: CGRect(x: 1800, y: 200, width: 2560, height: 1440),
        visibleFrame: CGRect(x: 1800, y: 200, width: 2560, height: 1416)
    )

    @Test func notchHangsFromTheTopCentre() {
        let layout = PillLayout(placement: .notch, geometry: notched)
        #expect(layout.panelFrame == CGRect(x: 400, y: 409, width: 1000, height: 760))
        #expect(layout.alignment == .top)
        #expect(layout.expandedWidth(scale: 1) == 440)
        #expect(layout.expandedWidth(scale: 2) == 704)
        #expect(PillLayout(placement: .notch, geometry: external).expandedWidth(scale: 1) == 440)
    }

    @Test func bottomCentreSitsAboveTheDock() {
        let layout = PillLayout(placement: .bottomCenter, geometry: notched)
        let frame = layout.panelFrame
        #expect(frame.midX == 900)
        #expect(frame.minY == 96)
        #expect(frame.size == CGSize(width: 1000, height: 760))
        #expect(layout.alignment == .bottom)
        #expect(layout.expandedWidth(scale: 1) == 424)
    }

    @Test func sideDockIsFlushWithTheRightEdge() {
        let layout = PillLayout(placement: .sideDock, geometry: external)
        let frame = layout.panelFrame
        #expect(frame.maxX == 4344)
        #expect(frame.maxY == 1246)
        #expect(frame.minY == 486)
        #expect(frame.width == 1000)
        #expect(layout.alignment == .topTrailing)
        #expect(layout.expandedWidth(scale: 1) == 440)
        #expect(frame.minY >= external.visibleFrame.minY + PillLayout.edgeMargin)
    }

    @Test func statusFitsCompactlyAndRepliesKeepTheirNormalWidth() {
        for placement in PillPlacement.allCases {
            let layout = PillLayout(placement: placement, geometry: notched)
            for scale: CGFloat in [1, 1.3, 1.6] {
                for state in [NotchState.thinking, .sending, .waiting] {
                    let width = layout.width(for: state, scale: scale)
                    #expect(width < layout.expandedWidth(scale: scale))
                    #expect(width > 100)
                    if placement == .notch {
                        #expect(width >= notched.notchWidth + 36)
                    }
                }
                for state in [
                    NotchState.listening,
                    .stillWorking,
                    .message("Ready."),
                    .reply(text: "Ready.", speaking: false, from: .assistant),
                    .call(.listening)
                ] {
                    #expect(layout.width(for: state, scale: scale) == layout.expandedWidth(scale: scale))
                }
            }
        }
    }

    @Test func floatingPanelsFitASmallScreen() {
        let small = NotchGeometry(
            hasNotch: false, notchWidth: 160, topBarHeight: 24,
            screenFrame: CGRect(x: 0, y: 0, width: 1024, height: 640),
            visibleFrame: CGRect(x: 0, y: 60, width: 1024, height: 556)
        )
        for placement in [PillPlacement.bottomCenter, .sideDock] {
            let frame = PillLayout(placement: placement, geometry: small).panelFrame
            #expect(small.visibleFrame.contains(frame), "\(placement) overflows the screen: \(frame)")
        }
    }

    @MainActor
    @Test func panelHidesAtRestOnlyInBottomCenter() async throws {
        let name = "NotchVoice.visibility.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: AppSettings.Key.fluidSpeechProAdopted)
        defaults.set("", forKey: AppSettings.Key.firstmateHome)
        let settings = AppSettings(defaults: defaults)
        let model = AppModel(settings: settings)
        let window = SettingsWindowController(dependencies: SettingsDependencies(
            settings: settings, model: model, library: ModelLibrary(), launchAtLogin: LaunchAtLogin(),
            developer: DeveloperActions(model: model), showOnboarding: {}
        ))
        let menu = StatusMenuBuilder(settings: settings, model: model, settingsWindow: window)
        let panel = NotchPanelController(model: model, menu: menu)
        defer { panel.window.orderOut(nil) }
        for placement in PillPlacement.allCases {
            settings.pillPlacement = placement
            panel.placementChanged()
            model.pendingReplies = 1
            panel.show()
            #expect(panel.window.isVisible == (placement != .bottomCenter))
            // The menu and hotkey share this action; missing models show a card without opening the mic.
            menu.makeMenu().performActionForItem(at: 0)
            try await Task.sleep(for: .milliseconds(100))
            #expect(model.state.isExpanded)
            #expect(panel.window.isVisible)
            for state in [NotchState.listening, .reply(text: "Ready.", speaking: false, from: .firstMate)] {
                model.state = state
                try await Task.sleep(for: .milliseconds(100))
                #expect(panel.window.isVisible)
            }
            model.dismiss()
            try await Task.sleep(for: .milliseconds(100))
            #expect(panel.window.isVisible == (placement != .bottomCenter))
        }
    }

    @MainActor
    @Test func renderedMorphKeepsItsAnchorWithAndWithoutAnimation() async throws {
        let name = "NotchVoice.morph.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: AppSettings.Key.fluidSpeechProAdopted)
        defaults.set("", forKey: AppSettings.Key.firstmateHome)
        let settings = AppSettings(defaults: defaults)
        // The test windows sit on screen; a pointer passing over one must not dismiss a reply mid-measurement.
        settings.autoDismissSeconds = 0
        let model = AppModel(settings: settings)
        let window = SettingsWindowController(dependencies: SettingsDependencies(
            settings: settings, model: model, library: ModelLibrary(), launchAtLogin: LaunchAtLogin(),
            developer: DeveloperActions(model: model), showOnboarding: {}
        ))
        let menu = StatusMenuBuilder(settings: settings, model: model, settingsWindow: window)
        for theme in CardTheme.allCases {
            settings.cardTheme = theme
            for disableAnimations in [false, true] {
                for placement in PillPlacement.allCases {
                    try await checkMorph(placement, disableAnimations: disableAnimations, model: model, menu: menu)
                }
            }
        }
    }

    @MainActor
    private func checkMorph(
        _ placement: PillPlacement, disableAnimations: Bool, model: AppModel, menu: StatusMenuBuilder
    ) async throws {
        let layout = PillLayout(placement: placement, geometry: notched)
        let hitArea = PillHitArea()
        let root = NotchRootView(model: model, layout: layout, hitArea: hitArea, menu: menu)
            .transaction {
                if disableAnimations {
                    $0.disablesAnimations = true
                }
            }
        let window = NotchPanel(contentRect: layout.panelFrame)
        window.contentView = NSHostingView(rootView: root)
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        var replyFrame = CGRect.zero
        for state in [
            NotchState.reply(text: "Ready for review.", speaking: false, from: .assistant),
            .thinking,
            .waiting,
            .reply(text: "Ready for review.", speaking: false, from: .assistant)
        ] {
            model.state = state
            try await Task.sleep(for: .milliseconds(650))
            let frame = hitArea.frame
            if replyFrame == .zero {
                replyFrame = frame
            }
            let dockWidth: CGFloat = placement == .sideDock ? DockColumn.talkSize + 4 + 16 : 0
            let expectedWidth = layout.width(for: state, scale: 1) + dockWidth
            #expect(
                abs(frame.width - expectedWidth) < 1,
                "\(placement) \(state): rendered \(frame.width), expected \(expectedWidth)"
            )
            switch placement {
            case .notch:
                #expect(abs(frame.midX - replyFrame.midX) < 1 && abs(frame.minY - replyFrame.minY) < 1)
            case .bottomCenter:
                #expect(abs(frame.midX - replyFrame.midX) < 1 && abs(frame.maxY - replyFrame.maxY) < 1)
            case .sideDock:
                #expect(abs(frame.maxX - replyFrame.maxX) < 1 && abs(frame.minY - replyFrame.minY) < 1)
            }
        }
    }

    @MainActor
    @Test func placementIsSavedAndDefaultsToTheNotch() throws {
        let name = "NotchVoice.placement.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults)
        #expect(settings.pillPlacement == .notch)
        var changes: [AppSettings.Change] = []
        settings.onChange = { changes.append($0) }
        settings.pillPlacement = .sideDock
        #expect(AppSettings(defaults: defaults).pillPlacement == .sideDock)
        #expect(changes.count == 1)
        defaults.set("ceiling", forKey: AppSettings.Key.pillPlacement)
        #expect(AppSettings(defaults: defaults).pillPlacement == .notch)
    }
}
