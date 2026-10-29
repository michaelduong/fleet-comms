//  MessengerModel.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation

enum MessengerModel: String, CaseIterable, Identifiable, Sendable {
    case haiku, codexLuna, grok, deepSeekFlash

    /// Only models meeting the measured five-second median limit belong in Settings.
    /// Keep candidates available to the opt-in subscription proof for future requalification.
    static let offered: [Self] = [.haiku]

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .haiku: "Claude Haiku · Claude"
        case .codexLuna: "GPT-6 Luna · Codex"
        case .grok: "Grok 4.7 · Grok"
        case .deepSeekFlash: "DeepSeek V4.1 Flash · OpenCode Go"
        }
    }

    var modelID: String {
        switch self {
        case .haiku: "haiku"
        case .codexLuna: "gpt-6-luna"
        case .grok: "grok-4.7"
        case .deepSeekFlash: "opencode-go/deepseek-v4.1-flash"
        }
    }

    var cli: String {
        switch self {
        case .haiku: "claude"
        case .codexLuna: "codex"
        case .grok: "grok"
        case .deepSeekFlash: "opencode"
        }
    }

    var executable: String? {
        let home = NSHomeDirectory()
        let candidates = [home + "/.local/bin/" + cli, "/opt/homebrew/bin/" + cli, "/usr/local/bin/" + cli]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
