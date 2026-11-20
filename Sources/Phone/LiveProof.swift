//  LiveProof.swift
//  FleetCommsPhone
//
//  Created by Michael Duong on 11/20/26.

import ActivityKit
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
            guard let id = activeCard?.id, activeCard?.content.state.phase == .thinking else {
                write("FAIL: no Thinking card to update before switching apps")
                return
            }
            write("waiting-background")
            while UIApplication.shared.applicationState != .background {
                try? await Task.sleep(for: .milliseconds(200))
            }
            await macStatesBeforeSpeechKeepTheCard(model, id: id, write: write)
        }

        /// FLC-59: exercise the handset and ActivityKit, not just the mapping from Mac states to card phases.
        @MainActor
        private static func macStatesBeforeSpeechKeepTheCard(
            _ model: PhoneModel, id: String, write: (String) -> Void
        ) async {
            let first = "Copy that, lab reply one."
            let last = "It has a second sentence."
            model.prove(stateMessage("reply"))
            var speech = PhoneMessage(.speech)
            speech.text = first + " " + last
            model.prove(speech)
            model.spokenOffset = first.utf16.count
            model.updateLive()
            try? await Task.sleep(for: .milliseconds(800))
            write("reply-off-screen \(model.liveProof)")
            guard activeCard?.id == id, activeCard?.content.state.phase == .speaking,
                  activeCard?.content.state.sentence == last else {
                write("FAIL: the original card did not show the off-screen reply")
                return
            }
            model.prove(PhoneMessage(.speechEnd))
            model.prove(stateMessage("idle"))
            try? await Task.sleep(for: .milliseconds(400))
            write("idle-keeps \(model.liveProof)")
            guard activeCard?.id == id, activeCard?.content.state.phase == .idle,
                  activeCard?.content.state.sentence == last else {
                write("FAIL: the original card did not keep the last sentence at idle")
                return
            }
            write("PASS: one activity showed Thinking, the off-screen reply, and the last sentence at idle")
        }

        private static var activeCard: Activity<CommsActivityAttributes>? {
            let active = Activity<CommsActivityAttributes>.activities.filter { $0.activityState == .active }
            return active.count == 1 ? active.first : nil
        }

        private static func stateMessage(_ state: String) -> PhoneMessage {
            var message = PhoneMessage(.state)
            message.state = state
            return message
        }
    }
#endif
