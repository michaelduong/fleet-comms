//  AskOptionRow.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/29/26.

import SwiftUI

/// One choice: its number, label and recommended mark, with a one-line description that opens out once chosen.
struct AskOptionRow: View {
    let option: AskQuestion.Option
    let number: Int
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 8) {
                Text("\(number)")
                    .notchFont(10, weight: .semibold)
                    .frame(width: 18, height: 18)
                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
                VStack(alignment: .leading, spacing: 2) {
                    title
                    if let description = option.description, !description.isEmpty {
                        Text(description)
                            .notchFont(11)
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(selected ? nil : 1)
                            .fixedSize(horizontal: false, vertical: true)
                            .help(description)
                            .accessibilityIdentifier("ask.option.\(number).description")
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .notchFont(13)
                    .foregroundStyle(selected ? Color.green : .white.opacity(0.4))
                    .padding(.top, 1)
            }
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(selected ? 0.16 : 0.05), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(tint.opacity(strokeOpacity)))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(Character(String(number))), modifiers: .command)
        .help("Choose (⌘\(number))")
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityIdentifier("ask.option.\(number)")
    }

    private var title: some View {
        HStack(spacing: 6) {
            Text(option.title)
                .notchFont(13, weight: .medium)
            if option.recommended {
                Text("Recommended")
                    .notchFont(9, weight: .semibold)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.green.opacity(0.2), in: Capsule())
                    .foregroundStyle(.green)
                    .accessibilityIdentifier("ask.option.\(number).recommended")
            }
        }
    }

    private var tint: Color {
        selected || option.recommended ? .green : .white
    }

    private var strokeOpacity: Double {
        if selected {
            return 0.6
        }
        return option.recommended ? 0.35 : 0.1
    }
}
