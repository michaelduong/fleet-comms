//  CollapsedPill.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import SwiftUI

/// The resting pill: the notch plus a small ear on each side. Click to talk.
struct CollapsedPill: View {
    let model: AppModel
    let geometry: NotchGeometry

    var body: some View {
        Button(action: model.talkPressed) {
            HStack(spacing: 0) {
                Image(systemName: "waveform")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: NotchGeometry.earWidth)
                    .accessibilityIdentifier("notch.collapsed.icon")
                Spacer(minLength: geometry.notchWidth)
                pendingIndicator
                    .frame(width: NotchGeometry.earWidth)
            }
            .frame(width: geometry.collapsedSize.width, height: geometry.collapsedSize.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.talkAccessibilityLabel)
        .accessibilityIdentifier("notch.collapsed.pill")
    }

    @ViewBuilder
    private var pendingIndicator: some View {
        if model.pendingReplies > 0 {
            Circle()
                .fill(.orange)
                .frame(width: 7, height: 7)
                .accessibilityIdentifier("notch.collapsed.pending")
        } else {
            Color.clear
        }
    }
}

extension AppModel {
    /// What the talk control is for, in every placement.
    var talkAccessibilityLabel: String {
        let action = pendingReplies > 0 ? "talk to Firstmate, reply pending" : "talk to Firstmate"
        return "Fleet Comms, \(action)"
    }
}
