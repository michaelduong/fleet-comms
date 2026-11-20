//  LiveProof.swift
//  FleetCommsPhone
//
//  Created by Michael Duong on 11/20/26.

import Foundation
import os
import UIKit

#if DEBUG
    /// Debug-only stand-in for a Mac reply that arrives while another app is in front.
    /// Launch with `--live-proof <log file>`. The runner brings the app forward, then another app.
    enum LiveProof {
        @MainActor
        static func start(_ model: PhoneModel) {
            let args = ProcessInfo.processInfo.arguments
            guard let index = args.firstIndex(of: "--live-proof"), args.count > index + 1 else { return }
            let path = args[index + 1]
            Task { @MainActor in await run(model, path: path) }
        }

        @MainActor
        private static func run(_ model: PhoneModel, path: String) async {
            let proofLog = Logger(subsystem: "live-proof", category: "proof")
            func write(_ line: String) {
                proofLog.error("\(line, privacy: .public)")
                let text = line + "\n"
                guard let data = text.data(using: .utf8) else { return }
                if FileManager.default.fileExists(atPath: path), let handle = FileHandle(forWritingAtPath: path) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                } else {
                    FileManager.default.createFile(atPath: path, contents: data)
                }
            }
            write("waiting-foreground \(model.liveProof)")
            while UIApplication.shared.applicationState != .active {
                try? await Task.sleep(for: .milliseconds(200))
            }
            for state in ["idle", "listening", "sending", "thinking"] {
                model.prove(stateMessage(state))
                try? await Task.sleep(for: .milliseconds(400))
            }
            write("card-up \(model.liveProof)")
            write("waiting-background")
            while UIApplication.shared.applicationState == .active {
                try? await Task.sleep(for: .milliseconds(200))
            }
            model.prove(stateMessage("reply"))
            var speech = PhoneMessage(.speech)
            speech.text = "Copy that, lab reply one. It has a second sentence."
            model.prove(speech)
            model.spokenOffset = "Copy that, lab reply one.".utf16.count
            model.updateLive()
            try? await Task.sleep(for: .milliseconds(800))
            write("reply-off-screen \(model.liveProof) sentence=\(model.lastSentence)")
            model.prove(PhoneMessage(.speechEnd))
            try? await Task.sleep(for: .milliseconds(400))
            model.prove(stateMessage("idle"))
            write("idle-keeps \(model.liveProof) sentence=\(model.lastSentence)")
        }

        private static func stateMessage(_ state: String) -> PhoneMessage {
            var message = PhoneMessage(.state)
            message.state = state
            return message
        }
    }
#endif
