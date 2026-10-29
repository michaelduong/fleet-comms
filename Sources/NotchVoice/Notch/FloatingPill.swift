//  FloatingPill.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import SwiftUI

/// The bottom card appears only while there is content to show.
struct FloatingPill: View {
    let model: AppModel
    let layout: PillLayout
    @Environment(\.notchScale) private var scale

    var body: some View {
        if model.displayState.isExpanded {
            FloatingCard(
                width: layout.width(for: model.displayState, scale: scale), theme: model.settings.cardTheme,
                status: model.displayState.compactStatusText
            ) {
                ExpandedContent(model: model)
            }
        }
    }
}

/// A themed rounded card for the expanded content, shared by the bottom and side placements.
struct FloatingCard<Content: View>: View {
    let width: CGFloat
    let theme: CardTheme
    var status: String?
    var hasDockPointer = false
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .modifier(PillMorph(width: width, status: status))
            .modifier(CardChrome(theme: theme, hasDockPointer: hasDockPointer))
            .accessibilityIdentifier("pill.floating.card")
    }
}

extension View {
    /// Black fill with a hairline and a soft shadow, so a floating pill reads on any wallpaper.
    func floatingChrome(cornerRadius: CGFloat, fill: Color = .black) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background(shape.fill(fill))
            .overlay(shape.strokeBorder(.white.opacity(0.18)))
            .clipShape(shape)
            .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
    }
}
