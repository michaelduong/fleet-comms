//  ListeningView.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import SwiftUI

struct ListeningView: View {
    let level: Float
    let transcript: String
    let hotkey: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                    .accessibilityIdentifier("notch.listening.micIndicator")
                LevelMeter(level: level)
                    .accessibilityIdentifier("notch.listening.level")
                Spacer(minLength: 0)
                Text("Esc or \(hotkey) to cancel")
                    .notchFont(11)
                    .foregroundStyle(.white.opacity(0.55))
                    .accessibilityIdentifier("notch.listening.hint")
            }
            TranscriptScroll(
                text: transcript.isEmpty ? "Listening…" : transcript,
                identifier: "notch.listening.transcript"
            )
            .foregroundStyle(transcript.isEmpty ? .white.opacity(0.6) : .white)
        }
    }
}

/// A row of bars that follows the mic level, tallest in the middle.
struct LevelMeter: View {
    let level: Float
    private let barCount = 12

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0 ..< barCount, id: \.self) { index in
                Capsule()
                    .fill(.white.opacity(0.85))
                    .frame(width: 3, height: barHeight(index))
            }
        }
        .frame(height: 22)
        .animation(.easeOut(duration: 0.08), value: level)
        .accessibilityElement()
        .accessibilityLabel("Microphone level")
        .accessibilityValue("\(Int(level * 100)) percent")
    }

    private func barHeight(_ index: Int) -> CGFloat {
        let centre = Double(barCount - 1) / 2
        let shape = 1 - abs(Double(index) - centre) / (centre + 1)
        return 3 + CGFloat(Double(level) * shape * 19)
    }
}
