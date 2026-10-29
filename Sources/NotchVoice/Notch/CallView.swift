//  CallView.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import SwiftUI

/// A realtime call: who is on the line, the mic level while the owner talks, and the latest words.
struct CallView: View {
    let lane: String
    let phase: CallPhase
    let level: Float
    let text: String
    let hotkey: String
    var autoScrolls = true
    var speechPlayback: SpeechPlayback?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Circle()
                    .fill(phase == .speaking ? .green : .red)
                    .frame(width: 8, height: 8)
                    .accessibilityIdentifier("notch.call.indicator")
                Text(status)
                    .notchFont(12, weight: .semibold)
                    .foregroundStyle(.white.opacity(0.75))
                    .accessibilityIdentifier("notch.call.status")
                if phase == .listening {
                    LevelMeter(level: level)
                        .accessibilityIdentifier("notch.call.level")
                }
                Spacer(minLength: 0)
                Text("Esc or \(hotkey) to hang up")
                    .notchFont(11)
                    .foregroundStyle(.white.opacity(0.55))
                    .accessibilityIdentifier("notch.call.hint")
            }
            if !text.isEmpty {
                TranscriptScroll(
                    text: text, identifier: "notch.call.text", autoScrolls: autoScrolls, speechPlayback: speechPlayback
                )
                .id(autoScrolls ? nil : text)
            }
        }
    }

    private var status: String {
        switch phase {
        case .connecting: "Connecting to \(lane)…"
        case .listening: lane
        case .speaking: "\(lane) is speaking"
        }
    }
}
