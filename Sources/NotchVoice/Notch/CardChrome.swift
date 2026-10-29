//  CardChrome.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import SwiftUI

struct CardChrome: ViewModifier {
    let theme: CardTheme
    let hasDockPointer: Bool

    func body(content: Content) -> some View {
        switch theme {
        case .dark:
            content.floatingChrome(cornerRadius: 20)
        case .glass:
            content.modifier(CardGlass(shape: FloatingCardShape(hasDockPointer: hasDockPointer)))
        }
    }
}

struct CardGlass<Surface: Shape>: ViewModifier {
    let shape: Surface
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        // Regular glass and the inherited dark appearance keep white text legible on any backdrop.
        if reduceTransparency {
            content.background(.black, in: shape)
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
        }
    }
}

/// One glass surface avoids a seam between the side card and its pointer.
private struct FloatingCardShape: Shape {
    let hasDockPointer: Bool

    func path(in rect: CGRect) -> Path {
        var path = RoundedRectangle(cornerRadius: 20, style: .continuous).path(in: rect)
        if hasDockPointer {
            path.addPath(DockPointer().path(in: CGRect(x: rect.maxX - 1, y: 15, width: 11, height: 18)))
        }
        return path
    }
}
