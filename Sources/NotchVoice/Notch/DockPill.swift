//  DockPill.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import AppKit
import SwiftUI

/// The side dock: a column of round buttons at the screen edge, with the open card beside it
/// pointing at the talk button it belongs to.
struct DockPill: View {
    let model: AppModel
    let layout: PillLayout
    let menu: StatusMenuBuilder
    @Environment(\.notchScale) private var scale

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            if model.displayState.isExpanded {
                FloatingCard(
                    width: layout.width(for: model.displayState, scale: scale), theme: model.settings.cardTheme,
                    status: model.displayState.compactStatusText, hasDockPointer: true
                ) {
                    ExpandedContent(model: model)
                }
                .overlay(alignment: .topTrailing) {
                    if model.settings.cardTheme == .dark {
                        DockPointer()
                            .fill(.black)
                            .frame(width: 10, height: 18)
                            .offset(x: 10, y: DockColumn.talkSize / 2 - 9)
                            .accessibilityHidden(true)
                    }
                }
            }
            DockColumn(model: model, menu: menu)
        }
    }
}

/// Talk, with the pending-reply badge, and the menu-bar menu as a "more" button.
struct DockColumn: View {
    static let talkSize: CGFloat = 44

    let model: AppModel
    let menu: StatusMenuBuilder

    var body: some View {
        VStack(spacing: 10) {
            DockButton(
                symbol: talkSymbol, size: Self.talkSize, fill: talkFill,
                label: model.talkAccessibilityLabel, identifier: "pill.dock.talk", action: model.talkPressed
            )
            .overlay(alignment: .topTrailing) { badge }
            DockButton(
                symbol: "ellipsis", size: 36, fill: .black, label: "Fleet Comms menu", identifier: "pill.dock.more"
            ) { menu.popUp(at: NSEvent.mouseLocation) }
        }
        .padding(2)
        .accessibilityIdentifier("pill.dock.column")
    }

    private var talkSymbol: String {
        switch model.state {
        case .listening: "mic.fill"
        case .call: "phone.down.fill"
        case .reply(_, true, _): "speaker.wave.2.fill"
        default: "waveform"
        }
    }

    /// Red while the mic is open, so the open card and the button tell the same story.
    private var talkFill: Color {
        switch model.state {
        case .listening, .call(.listening): .red
        case .call: Color(red: 0.1, green: 0.5, blue: 0.25)
        default: .black
        }
    }

    @ViewBuilder
    private var badge: some View {
        if model.pendingReplies > 0 {
            Text("\(model.pendingReplies)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 5)
                .frame(minWidth: 18, minHeight: 18)
                .fixedSize()
                .background(.orange, in: Capsule())
                .accessibilityIdentifier("pill.dock.pending")
        }
    }
}

struct DockButton: View {
    let symbol: String
    let size: CGFloat
    let fill: Color
    let label: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .semibold))
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .floatingChrome(cornerRadius: size / 2, fill: fill)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

/// A small triangle on the card's right edge, pointing at the button in the column.
struct DockPointer: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
