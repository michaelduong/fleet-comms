//  MenuPlacement.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import CoreGraphics

/// Where the menu's top-left corner goes, in screen coordinates (origin bottom-left).
/// macOS hides a status item that does not fit beside the notch and parks its window away from
/// the menu bar; a menu anchored to that frame lands in a screen corner, so it goes elsewhere then.
enum MenuPlacement {
    struct Screen {
        let frame: CGRect
        let visibleFrame: CGRect
        var safeAreaTop: CGFloat = 0

        /// The visible frame reports no menu bar while it auto-hides, so the notch inset
        /// and a standard bar height stand in.
        var menuBarHeight: CGFloat {
            max(frame.maxY - visibleFrame.maxY, safeAreaTop, 24)
        }

        var belowMenuBar: CGFloat {
            frame.maxY - menuBarHeight
        }
    }

    static func origin(itemFrame: CGRect?, mouse: CGPoint, screens: [Screen], notchScreen: Screen?) -> CGPoint {
        if let itemFrame, screens.contains(where: { isInMenuBar(itemFrame, of: $0) }) {
            return CGPoint(x: itemFrame.minX, y: itemFrame.minY)
        }
        // Clicked from a menu-bar overflow: open where the click was.
        if let screen = screens.first(where: { $0.frame.contains(mouse) }),
           mouse.y >= screen.belowMenuBar {
            return CGPoint(x: mouse.x, y: screen.belowMenuBar)
        }
        // Opened some other way (keyboard, accessibility): under the notch.
        guard let screen = notchScreen ?? screens.first else { return mouse }
        return CGPoint(x: screen.frame.midX - 120, y: screen.belowMenuBar)
    }

    /// A shown status item sits in the strip at the very top of a screen.
    static func isInMenuBar(_ itemFrame: CGRect, of screen: Screen) -> Bool {
        screen.frame.contains(itemFrame) && abs(itemFrame.maxY - screen.frame.maxY) <= 2
    }
}
