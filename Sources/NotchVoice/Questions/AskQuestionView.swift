//  AskQuestionView.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/29/26.

import SwiftUI

/// A Claude question inside the pill, on the same surface and at the same width as listening and replies.
struct AskQuestionView: View {
    let store: AskQuestionStore
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let request = store.current, let question = store.question {
                header(request, question: question)
                AskQuestionText(text: question.question)
                ForEach(question.options.indices, id: \.self) { index in
                    AskOptionRow(
                        option: question.options[index], number: index + 1,
                        selected: store.draft.selected.contains(index),
                        action: { store.select(index) }
                    )
                }
                AskReplyRow(store: store, model: model)
                footer(request, question: question)
            } else if let confirmation = store.confirmation {
                Label(confirmation, systemImage: "checkmark.circle.fill")
                    .notchFont(13, weight: .medium)
                    .foregroundStyle(.green)
                    .accessibilityIdentifier("ask.confirmation")
            }
        }
        .accessibilityIdentifier("ask.card")
    }

    private func header(_ request: AskRequest, question: AskQuestion) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "questionmark.bubble.fill")
                .notchFont(12)
                .accessibilityIdentifier("ask.icon")
            if request.questions.count > 1 {
                pages(request)
            } else {
                Text(question.header)
                    .notchFont(12, weight: .semibold)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .accessibilityIdentifier("ask.topic")
            }
            Spacer(minLength: 0)
            if store.requests.count > 1 {
                Text("\(store.requests.count) waiting")
                    .notchFont(10, weight: .medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.1), in: Capsule())
                    .accessibilityLabel("\(store.requests.count) unanswered requests")
                    .accessibilityIdentifier("ask.inbox")
            }
            DismissButton(action: store.dismiss, identifier: "ask.close", label: "Close and answer in the terminal")
                .keyboardShortcut(.cancelAction)
                .help("Answer in the terminal (Esc)")
        }
    }

    private func pages(_ request: AskRequest) -> some View {
        HStack(spacing: 4) {
            ForEach(request.questions.indices, id: \.self) { index in
                Button { store.go(to: index) } label: {
                    Text(request.questions[index].header)
                        .notchFont(10, weight: .medium)
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.white.opacity(store.page == index ? 0.18 : 0.06), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(store.sending)
                .accessibilityValue(store.page == index ? "Current page" : "")
                .accessibilityIdentifier("ask.page.\(index)")
            }
        }
    }

    private func footer(_ request: AskRequest, question: AskQuestion) -> some View {
        HStack(spacing: 8) {
            Text(status(request, question: question))
                .notchFont(11)
                .foregroundStyle(store.error == nil ? Color.white.opacity(0.55) : .orange)
                .lineLimit(1)
                .accessibilityIdentifier("ask.status")
            Spacer(minLength: 0)
            if store.page + 1 < request.questions.count {
                Button("Next question") { store.go(to: store.page + 1) }
                    .buttonStyle(.plain)
                    .notchFont(11, weight: .medium)
                    .disabled(store.sending)
                    .accessibilityIdentifier("ask.next")
            }
        }
    }

    private func status(_ request: AskRequest, question: AskQuestion) -> String {
        if let error = store.error {
            return error
        }
        if store.sending {
            return "Sending…"
        }
        var parts = [request.agent]
        if request.questions.count > 1 {
            parts.append("\(store.page + 1) of \(request.questions.count)")
        }
        if question.multiSelect == true {
            parts.append("choose all that apply")
        }
        return parts.joined(separator: " · ")
    }
}
