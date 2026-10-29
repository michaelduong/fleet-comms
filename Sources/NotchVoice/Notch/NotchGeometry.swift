//  NotchGeometry.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import AppKit

/// Where the camera housing sits on a screen, or a stand-in strip at the top
/// centre of a screen without one, plus the room the screen leaves beside the Dock and menu bar.
struct NotchGeometry: Equatable {
    let hasNotch: Bool
    let notchWidth: CGFloat
    let topBarHeight: CGFloat
    let screenFrame: CGRect
    let visibleFrame: CGRect

    /// The visible "ears" either side of the notch in the collapsed pill.
    static let earWidth: CGFloat = 30

    init(screen: NSScreen) {
        screenFrame = screen.frame
        visibleFrame = screen.visibleFrame
        let inset = screen.safeAreaInsets.top
        if inset > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            hasNotch = true
            notchWidth = screen.frame.width - left.width - right.width
            topBarHeight = inset
        } else {
            hasNotch = false
            notchWidth = 160
            topBarHeight = max(NSStatusBar.system.thickness, 24)
        }
    }

    init(hasNotch: Bool, notchWidth: CGFloat, topBarHeight: CGFloat, screenFrame: CGRect, visibleFrame: CGRect) {
        self.hasNotch = hasNotch
        self.notchWidth = notchWidth
        self.topBarHeight = topBarHeight
        self.screenFrame = screenFrame
        self.visibleFrame = visibleFrame
    }

    var collapsedSize: CGSize {
        CGSize(width: notchWidth + Self.earWidth * 2, height: topBarHeight)
    }

    /// A frame of `size` hanging from the top edge, centred on the notch.
    func frame(for size: CGSize) -> CGRect {
        CGRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }
}
