//  ReplyView.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import AppKit
import SwiftUI

/// A reply from the first mate or the assistant, shown while it is spoken.
struct ReplyView: View {
    let text: String
    let speaking: Bool
    let source: ReplySource
    let onDismiss: () -> Void
    var speechPlayback: SpeechPlayback?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .accessibilityLabel("Fleet Comms")
                    .accessibilityIdentifier("notch.reply.icon")
                Text(source.title)
                    .notchFont(12, weight: .semibold)
                    .foregroundStyle(.white.opacity(0.7))
                    .accessibilityIdentifier("notch.reply.title")
                Spacer(minLength: 0)
                DismissButton(action: onDismiss, identifier: "notch.reply.dismiss")
            }
            TranscriptScroll(
                text: text, identifier: "notch.reply.text", autoScrolls: false, speechPlayback: speechPlayback
            )
            .id(text)
        }
    }
}
