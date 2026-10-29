//  NotchRootView.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import SwiftUI

/// The pill, pinned to the panel edge its placement grows from. Collapsed controls stay black.
struct NotchRootView: View {
    let model: AppModel
    let layout: PillLayout
    let hitArea: PillHitArea
    let menu: StatusMenuBuilder
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content
            .animation(PillMorph.animation(reduceMotion: reduceMotion), value: model.displayState.compactStatusText)
            .accessibilityIdentifier("pill.content")
            .environment(\.notchScale, model.settings.textSize.scale)
            .foregroundStyle(.white)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { hitArea.frame = $0 }
            .onHover { model.setPillHovered($0) }
            .environment(\.colorScheme, .dark)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: layout.alignment)
    }

    @ViewBuilder
    private var content: some View {
        switch layout.placement {
        case .notch: NotchPill(model: model, layout: layout)
        case .bottomCenter: FloatingPill(model: model, layout: layout)
        case .sideDock: DockPill(model: model, layout: layout, menu: menu)
        }
    }
}

/// The pill that grows out of the camera housing: the ears at rest, a card below the notch when open.
struct NotchPill: View {
    let model: AppModel
    let layout: PillLayout
    @Environment(\.notchScale) private var scale

    var body: some View {
        if model.displayState.isExpanded, model.settings.cardTheme == .glass {
            content
                .modifier(CardGlass(shape: NotchShape(radius: 20)))
                .accessibilityIdentifier("pill.notch.card")
        } else {
            content
                .background(NotchShape(radius: model.displayState.isExpanded ? 20 : 10).fill(.black))
                .clipShape(NotchShape(radius: model.displayState.isExpanded ? 20 : 10))
                .accessibilityIdentifier("pill.notch.card")
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.displayState.isExpanded {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: layout.geometry.topBarHeight)
                ExpandedContent(model: model)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 14)
                    .padding(.top, 4)
            }
            .modifier(PillMorph(
                width: layout.width(for: model.displayState, scale: scale),
                status: model.displayState.compactStatusText
            ))
        } else {
            CollapsedPill(model: model, geometry: layout.geometry)
        }
    }
}

/// Square top corners flush with the screen edge, rounded bottom corners.
struct NotchShape: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(
            roundedRect: rect,
            cornerRadii: RectangleCornerRadii(bottomLeading: radius, bottomTrailing: radius)
        )
    }
}

extension EnvironmentValues {
    @Entry var notchScale: CGFloat = 1
}

extension View {
    func notchFont(_ size: CGFloat, weight: Font.Weight = .regular) -> some View {
        modifier(NotchFont(size: size, weight: weight))
    }
}

private struct NotchFont: ViewModifier {
    @Environment(\.notchScale) private var scale
    let size: CGFloat
    let weight: Font.Weight

    func body(content: Content) -> some View {
        content.font(.system(size: size * scale, weight: weight))
    }
}
