//  TranscriptScroll.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import SwiftUI

/// Live transcripts follow new text; replies follow audio playback until the owner scrolls.
struct TranscriptScroll: View {
    @Environment(\.notchScale) private var scale
    let text: String
    let identifier: String
    var autoScrolls = true
    var speechPlayback: SpeechPlayback?
    @State private var position = ScrollPosition(y: 0)
    @State private var followsSpeech = true
    @State private var spokenHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var textHeight: CGFloat = 0
    @State private var followsLatest = true
    @State private var userScrolling = false
    @State private var nearBottom = true

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Text(attributed)
                        .notchFont(14)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { textHeight = $0 }
                        .accessibilityIdentifier(identifier)
                        .overlay(alignment: .topLeading) { measuredSpokenPrefix }
                    Color.clear.frame(height: 1).id("transcript.bottom")
                        .accessibilityHidden(true)
                }
            }
            .frame(height: min(max(24, textHeight + 1), 300 * min(scale, 1.6)))
            .scrollIndicators(.automatic)
            .scrollPosition($position)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 12
            } action: { _, bottom in
                nearBottom = bottom
                if userScrolling {
                    followsLatest = bottom
                }
            }
            .onScrollPhaseChange { _, phase in
                userScrolling = phase != .idle && phase != .animating
                if userScrolling {
                    followsSpeech = false
                }
                if phase == .idle {
                    followsLatest = nearBottom
                }
            }
            .onChange(of: textHeight) {
                if autoScrolls, followsLatest {
                    proxy.scrollTo("transcript.bottom", anchor: .bottom)
                }
            }
            .onChange(of: speechPlayback?.id) {
                guard speechPlayback != nil else { return }
                followsSpeech = true
                position.scrollTo(y: 0)
            }
            .onChange(of: spokenHeight) {
                guard followsSpeech, speechPlayback != nil else { return }
                let target = max(0, spokenHeight - viewportHeight * 0.3)
                withAnimation(reduceMotion ? nil : .linear(duration: 0.18)) {
                    position.scrollTo(y: target)
                }
            }
            .accessibilityIdentifier(identifier + ".scroll")
        }
    }

    @ViewBuilder private var measuredSpokenPrefix: some View {
        if let prefix = spokenPrefix {
            Text(prefix)
                .notchFont(14)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .hidden()
                .accessibilityHidden(true)
                .allowsHitTesting(false)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { spokenHeight = $0 }
        }
    }

    private var spokenPrefix: AttributedString? {
        guard let speechPlayback else { return nil }
        let full = attributed
        let visible = String(full.characters)
        let offset = speechPlayback.displayOffset(in: visible)
        let end = String.Index(utf16Offset: offset, in: visible)
        let boundary = full.characters.index(
            full.startIndex,
            offsetBy: visible.distance(from: visible.startIndex, to: end)
        )
        return AttributedString(full[..<boundary])
    }

    private var attributed: AttributedString {
        attributed(text)
    }

    private func attributed(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
