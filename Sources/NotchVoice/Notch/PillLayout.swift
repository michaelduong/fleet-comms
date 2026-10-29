//  PillLayout.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import AppKit
import SwiftUI

/// Where the panel sits on its screen for each placement, and which edge of that panel the pill
/// grows from. The content views are the same everywhere; only this anchoring changes.
struct PillLayout: Equatable {
    /// Room for the widest and tallest pill, at the largest text size.
    static let canvasSize = CGSize(width: 1000, height: 760)
    /// Gap between a floating pill and the screen edge, the Dock or the menu bar.
    static let edgeMargin: CGFloat = 16

    let placement: PillPlacement
    let geometry: NotchGeometry

    /// The panel's frame in screen coordinates (origin bottom-left).
    var panelFrame: CGRect {
        switch placement {
        case .notch: geometry.frame(for: Self.canvasSize)
        case .bottomCenter: bottomFrame
        case .sideDock: sideFrame
        }
    }

    /// The edge of the panel the pill is pinned to, so it grows away from the screen edge.
    var alignment: Alignment {
        switch placement {
        case .notch: .top
        case .bottomCenter: .bottom
        case .sideDock: .topTrailing
        }
    }

    /// A notch pill must span the housing; a floating card only needs room for its text.
    func expandedWidth(scale: CGFloat) -> CGFloat {
        let text = 440 * min(scale, 1.6)
        switch placement {
        case .notch: return max(geometry.notchWidth + 140, text)
        case .bottomCenter: return text - 16
        case .sideDock: return text
        }
    }

    func width(for state: NotchState, scale: CGFloat) -> CGFloat {
        guard let text = state.compactStatusText else { return expandedWidth(scale: scale) }
        let font = NSFont.systemFont(ofSize: 13 * scale, weight: .medium)
        let textWidth = (text as NSString).size(withAttributes: [.font: font]).width
        let statusWidth = ceil(textWidth) + 16 * scale + 10 + 36
        // The top edge must continue to cover the camera housing while the status shrinks.
        return placement == .notch ? max(geometry.notchWidth + 36, statusWidth) : statusWidth
    }

    /// Centred above the Dock; the pill grows upwards from the bottom of the panel.
    private var bottomFrame: CGRect {
        let visible = geometry.visibleFrame
        let size = CGSize(
            width: min(Self.canvasSize.width, visible.width),
            height: min(Self.canvasSize.height, visible.height - Self.edgeMargin * 2)
        )
        return CGRect(
            x: visible.midX - size.width / 2, y: visible.minY + Self.edgeMargin,
            width: size.width, height: size.height
        )
    }

    /// Flush with the right edge, starting a quarter of the way down the screen so a card has
    /// room to grow below the column of buttons.
    private var sideFrame: CGRect {
        let visible = geometry.visibleFrame
        let top = visible.maxY - Self.edgeMargin - visible.height / 4
        let size = CGSize(
            width: min(Self.canvasSize.width, visible.width - Self.edgeMargin),
            height: min(Self.canvasSize.height, top - visible.minY - Self.edgeMargin)
        )
        return CGRect(
            x: visible.maxX - Self.edgeMargin - size.width, y: top - size.height,
            width: size.width, height: size.height
        )
    }
}

/// Lay text out at its destination width once; only the clipped outer bounds interpolate.
struct PillMorph: ViewModifier {
    let width: CGFloat
    let status: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var height: CGFloat?
    @State private var appeared = false
    @State private var revealed = true

    func body(content: Content) -> some View {
        content
            .frame(width: width, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { updated in
                withAnimation(height == nil ? nil : Self.animation(reduceMotion: reduceMotion)) { height = updated }
            }
            .transaction { $0.animation = nil }
            .opacity(revealed ? 1 : 0)
            .frame(width: width, height: height, alignment: .topLeading)
            .clipped()
            .task(id: status) { await revealContent() }
    }

    static func animation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.85)
    }

    private func revealContent() async {
        guard appeared else {
            appeared = true
            return
        }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { revealed = false }
        if !reduceMotion {
            do { try await Task.sleep(for: .milliseconds(240)) } catch { return }
        }
        guard !Task.isCancelled else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) { revealed = true }
    }
}
