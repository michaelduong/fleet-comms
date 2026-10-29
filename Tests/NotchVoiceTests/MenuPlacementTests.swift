//  MenuPlacementTests.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import CoreGraphics
@testable import NotchVoice
import Testing

struct MenuPlacementTests {
    /// This Mac's built-in display: 1800 x 1169 points, 38 pt notch, menu bar auto-hidden.
    private let screen = MenuPlacement.Screen(
        frame: CGRect(x: 0, y: 0, width: 1800, height: 1169),
        visibleFrame: CGRect(x: 0, y: 0, width: 1800, height: 1130),
        safeAreaTop: 38
    )

    @Test func visibleItemAnchorsUnderItself() {
        let item = CGRect(x: 1500, y: 1145, width: 24, height: 24)
        let origin = MenuPlacement.origin(itemFrame: item, mouse: .zero, screens: [screen], notchScreen: screen)
        #expect(origin == CGPoint(x: 1500, y: 1145))
    }

    @Test func hiddenItemOpensAtAMenuBarClick() {
        let hidden = CGRect(x: 0, y: 0, width: 24, height: 24)
        let mouse = CGPoint(x: 1300, y: 1160)
        let origin = MenuPlacement.origin(itemFrame: hidden, mouse: mouse, screens: [screen], notchScreen: screen)
        #expect(origin == CGPoint(x: 1300, y: 1130))
    }

    @Test func hiddenItemOtherwiseOpensUnderTheNotch() {
        let hidden = CGRect(x: 0, y: 0, width: 24, height: 24)
        let mouse = CGPoint(x: 300, y: 500)
        let origin = MenuPlacement.origin(itemFrame: hidden, mouse: mouse, screens: [screen], notchScreen: screen)
        #expect(origin == CGPoint(x: 780, y: 1130))
    }
}
