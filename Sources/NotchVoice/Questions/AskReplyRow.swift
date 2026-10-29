//  AskReplyRow.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/29/26.

import SwiftUI

/// A typed or dictated free-text answer. While dictating, the live meter and transcript take the field's place.
struct AskReplyRow: View {
    let store: AskQuestionStore
    let model: AppModel

    private var dictating: Bool {
        model.questionDictation != nil
    }

    var body: some View {
        HStack(spacing: 8) {
            if dictating {
                LevelMeter(level: model.level)
                    .accessibilityIdentifier("ask.dictation.level")
                Text(model.transcript.isEmpty ? "Listening…" : model.transcript)
                    .notchFont(13)
                    .lineLimit(2)
                    .foregroundStyle(.white.opacity(model.transcript.isEmpty ? 0.6 : 1))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("ask.dictation.transcript")
            } else {
                TextField(
                    "Or type a reply…", text: Binding(get: { store.draft.text }, set: { store.type($0) }),
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .lineLimit(1 ... 3)
                .notchFont(13)
                .disabled(store.sending)
                .accessibilityIdentifier("ask.reply")
            }
            Button(action: model.toggleQuestionDictation) {
                Image(systemName: dictating ? "stop.circle.fill" : "mic")
                    .notchFont(14)
                    .foregroundStyle(dictating ? Color.red : .white.opacity(0.7))
            }
            .buttonStyle(.plain)
            .disabled(store.sending)
            .help(dictating ? "Stop dictating" : "Dictate a reply")
            .accessibilityLabel(dictating ? "Stop dictating" : "Dictate a reply")
            .accessibilityIdentifier("ask.microphone")
            Button(action: store.send) {
                Image(systemName: "arrow.up.circle.fill")
                    .notchFont(18)
            }
            .buttonStyle(.plain)
            .disabled(!store.canSend)
            .keyboardShortcut(.return, modifiers: .command)
            .foregroundStyle(store.canSend ? Color.green : .white.opacity(0.4))
            .help("Send (⌘↩)")
            .accessibilityLabel("Send answers")
            .accessibilityIdentifier("ask.send")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.09)))
    }
}
