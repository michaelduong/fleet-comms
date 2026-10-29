//  ExpandedContent.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import SwiftUI

struct ExpandedContent: View {
    let model: AppModel

    var body: some View {
        switch model.displayState {
        case .idle:
            EmptyView()
        case .question:
            AskQuestionView(store: model.questions, model: model)
        case let .preparing(activity, step, fraction):
            PreparingView(activity: activity, step: step, fraction: fraction)
        case .listening:
            ListeningView(level: model.level, transcript: model.transcript, hotkey: model.settings.hotkey.title)
        case .thinking:
            StatusLine(
                text: model.state.compactStatusText ?? "", showsSpinner: true, identifier: "notch.thinking.status"
            )
        case .sending:
            StatusLine(
                text: model.state.compactStatusText ?? "", showsSpinner: true, identifier: "notch.sending.status"
            )
        case .waiting:
            StatusLine(
                text: model.state.compactStatusText ?? "", showsSpinner: true, identifier: "notch.waiting.status"
            )
        case .stillWorking:
            StatusLine(
                text: "Still working. The reply will be spoken when it lands.",
                showsSpinner: false,
                identifier: "notch.stillWorking.status"
            )
        case let .reply(text, speaking, source):
            ReplyView(
                text: text, speaking: speaking, source: source, onDismiss: model.dismiss,
                speechPlayback: model.speechPlayback
            )
        case let .message(text):
            MessageView(text: text, onDismiss: model.dismiss)
        case let .call(phase):
            CallView(
                lane: model.call?.provider.title ?? model.settings.voiceLane.title, phase: phase,
                level: model.level, text: model.transcript, hotkey: model.settings.hotkey.title,
                // Supplied outreach is a reply to read from the top, until the live conversation starts.
                autoScrolls: model.call?.outreach?.completed != false,
                speechPlayback: model.call?.outreach?.completed == false ? model.speechPlayback : nil
            )
        }
    }
}

struct PreparingView: View {
    let activity: String
    let step: String
    let fraction: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .notchFont(13, weight: .medium)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("notch.preparing.title")
            if let fraction {
                ProgressView(value: fraction)
                    .tint(.white)
                    .accessibilityIdentifier("notch.preparing.progress")
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(.white)
                    .accessibilityIdentifier("notch.preparing.progress")
            }
        }
    }

    private var title: String {
        let base = "\(activity) \(step.lowercased())"
        guard let fraction else { return base + "…" }
        return base + " · \(Int(fraction * 100))%"
    }
}

struct StatusLine: View {
    let text: String
    let showsSpinner: Bool
    let identifier: String
    @Environment(\.notchScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if showsSpinner {
                Image(systemName: "ellipsis")
                    .notchFont(13, weight: .bold)
                    .frame(width: 16 * scale)
                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: !reduceMotion)
                    .accessibilityIdentifier(identifier + ".spinner")
            }
            Text(text)
                .notchFont(13, weight: .medium)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(identifier)
        }
    }
}

struct MessageView: View {
    let text: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(text)
                .notchFont(13, weight: .medium)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("notch.message.text")
            DismissButton(action: onDismiss, identifier: "notch.message.dismiss")
        }
    }
}

struct DismissButton: View {
    let action: () -> Void
    let identifier: String
    var label = "Dismiss"

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .notchFont(16)
                .foregroundStyle(.white.opacity(0.7))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}
