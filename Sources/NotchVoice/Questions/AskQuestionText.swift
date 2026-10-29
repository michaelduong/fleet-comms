//  AskQuestionText.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/29/26.

import SwiftUI

/// The question at body size: three lines at first, with the rest behind Show more.
struct AskQuestionText: View {
    let text: String
    @State private var expanded = false
    @State private var fullHeight: CGFloat = 0
    @State private var shownHeight: CGFloat = 0

    private var truncated: Bool {
        fullHeight > shownHeight + 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(text)
                .notchFont(13, weight: .medium)
                .lineLimit(expanded ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { shownHeight = $0 }
                .background { fullMeasure }
                .accessibilityIdentifier("ask.question")
            if truncated || expanded {
                Button(expanded ? "Show less" : "Show more") { expanded.toggle() }
                    .buttonStyle(.plain)
                    .notchFont(11, weight: .medium)
                    .foregroundStyle(.white.opacity(0.6))
                    .accessibilityIdentifier("ask.more")
            }
        }
    }

    /// The unlimited text laid out at the same width, so a question that fits shows no toggle.
    private var fullMeasure: some View {
        Text(text)
            .notchFont(13, weight: .medium)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hidden()
            .accessibilityHidden(true)
            .allowsHitTesting(false)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
    }
}
