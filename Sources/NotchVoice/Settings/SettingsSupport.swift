//  SettingsSupport.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A one-line state with a coloured symbol: ready, needs attention, or missing.
struct StatusText: View {
    enum Tone {
        case ready
        case warning
        case missing
        case neutral
    }

    let tone: Tone
    let text: String
    let identifier: String

    var body: some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(color)
        }
        .font(.callout)
        .accessibilityIdentifier(identifier)
    }

    private var symbol: String {
        switch tone {
        case .ready: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .missing: "xmark.circle.fill"
        case .neutral: "info.circle"
        }
    }

    private var color: Color {
        switch tone {
        case .ready: .green
        case .warning: .orange
        case .missing: .red
        case .neutral: .secondary
        }
    }
}

/// One row of a window's left-hand rail: an icon, a title and a tint when selected.
struct RailRow: View {
    let title: String
    let symbol: String
    let selected: Bool
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol).frame(width: 22)
            }
            .font(.body.weight(selected ? .semibold : .regular))
            .foregroundStyle(selected ? .primary : .secondary)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color.accentColor.opacity(0.15) : .clear, in: .rect(cornerRadius: 6))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

/// Secondary explanatory text under a control.
struct SettingsNote: View {
    let text: String
    let identifier: String

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(identifier)
    }
}

@MainActor
enum PathChooser {
    static func chooseFolder(title: String, startingAt path: String = "") -> String? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        if !path.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: path)
        }
        NSApp.activate()
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    static func chooseFile(title: String, types: [UTType] = [.item]) -> String? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseDirectories = false
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.treatsFilePackagesAsDirectories = true
        NSApp.activate()
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}

enum ByteCount {
    static func string(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

extension String {
    /// A path with the home folder shown as `~`, for display only.
    var abbreviatingHome: String {
        (self as NSString).abbreviatingWithTildeInPath
    }
}
