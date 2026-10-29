//  AppSettings+ClaudeCLI.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation

extension AppSettings {
    static let claudeCandidates = ["/.local/bin/claude", "/.claude/local/claude"].map { NSHomeDirectory() + $0 }
        + ["/opt/homebrew/bin/claude", "/usr/local/bin/claude"]

    var resolvedClaudePath: String {
        guard claudePath.isEmpty else { return claudePath }
        let candidates = Self.claudeCandidates
        return candidates.first(where: FileManager.default.isExecutableFile(atPath:)) ?? candidates[0]
    }

    var claudeCLIFound: Bool {
        FileManager.default.isExecutableFile(atPath: resolvedClaudePath)
    }
}
