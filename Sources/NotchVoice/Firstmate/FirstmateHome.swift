//  FirstmateHome.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation

/// Finds firstmate homes on this Mac: `FM_HOME` when set, and the folders under the standard
/// install root that carry `bin/fm-inbox.sh`. Nothing is assumed about their names.
enum FirstmateHome {
    static let installRoot = NSHomeDirectory() + "/.local/share/production-agent-stack/firstmate"
    static let inboxScriptPath = "bin/fm-inbox.sh"

    static func inboxScript(in home: String) -> String {
        home + "/" + inboxScriptPath
    }

    /// A home is usable when its inbox script can be run.
    static func isValid(_ home: String) -> Bool {
        !home.isEmpty && FileManager.default.isExecutableFile(atPath: inboxScript(in: home))
    }

    static func candidates(
        under root: String = installRoot,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String] {
        var found: [String] = []
        if let fromEnvironment = environment["FM_HOME"], isValid(fromEnvironment) {
            found.append(fromEnvironment)
        }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
        for name in names.sorted() {
            let home = root + "/" + name
            if isValid(home), !found.contains(home) {
                found.append(home)
            }
        }
        return found
    }

    /// The default for a fresh install: the only home found, else none, so onboarding asks.
    static func defaultHome(
        under root: String = installRoot,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        let homes = candidates(under: root, environment: environment)
        return homes.count == 1 ? homes[0] : ""
    }
}
