//  RealtimeLookupProofTests.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import AppKit
import Foundation
@testable import NotchVoice
import SwiftUI
import Testing

#if DEBUG
    @MainActor
    struct RealtimeLookupProofTests {
        @Test func liveOutreachReadsSuppliedText() async throws {
            let environment = ProcessInfo.processInfo.environment
            guard let root = environment["FLEET_COMMS_OUTREACH_PROOF_ROOT"],
                  let wav = environment["FLEET_COMMS_OUTREACH_PROOF_WAV"],
                  let text = environment["FLEET_COMMS_OUTREACH_PROOF_TEXT"] else { return }
            try #require(Bundle.main.bundleIdentifier?.hasPrefix("com.fleetcomms.proof.") == true)
            let provider: RealtimeProvider = environment["FLEET_COMMS_OUTREACH_PROOF_LANE"] == "chatgpt" ?
                .chatGPT : .grok
            let reading = RealtimeOutreach(reply: .init(id: "reading-proof", text: text))
            let call = RealtimeCall(
                provider: provider,
                voice: environment["FLEET_COMMS_REALTIME_PROOF_VOICE"] ?? (provider == .grok ? "rex" : "marin"),
                source: .wav(URL(fileURLWithPath: wav)), silenceSeconds: 0.8, idleHangUp: 25, outreach: reading
            ) { "Be brief." }
            let delegate = RealtimeLookupDelegate()
            call.delegate = delegate
            defer { call.end() }
            call.start()
            let deadline = Date().addingTimeInterval(60)
            while !call.ended, !reading.completed, Date() < deadline {
                try await Task.sleep(for: .milliseconds(100))
            }
            let result = [
                "supplied": text,
                "transcript": reading.transcript,
                "completed": String(reading.completed),
                "error": delegate.failure?.code ?? "none"
            ]
            let folder = URL(fileURLWithPath: root)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
                .write(to: folder.appendingPathComponent("\(provider.id)-reading.json"))
            #expect(reading.completed)
            #expect(delegate.failure == nil)
        }

        @Test func liveLookupSpeaksFolder() async throws {
            let environment = ProcessInfo.processInfo.environment
            guard let root = environment["FLEET_COMMS_REALTIME_PROOF_ROOT"],
                  let wav = environment["FLEET_COMMS_REALTIME_PROOF_WAV"],
                  let data = environment["FLEET_COMMS_REALTIME_PROOF_DATA"],
                  let expected = environment["FLEET_COMMS_REALTIME_PROOF_EXPECTED_FOLDER"] else { return }
            try #require(Bundle.main.bundleIdentifier?.hasPrefix("com.fleetcomms.proof.") == true)
            try #require(expected.hasPrefix("/") && expected != "/", "Supply the exact absolute screenshot folder.")
            let expectedFolder = expected.hasSuffix("/") ? String(expected.dropLast()) : expected
            let provider: RealtimeProvider = environment["FLEET_COMMS_REALTIME_PROOF_LANE"] == "chatgpt" ? .chatGPT :
                .grok
            let outreach = environment["FLEET_COMMS_REALTIME_PROOF_OUTREACH"] == "1" ?
                RealtimeOutreach(reply: .init(id: "proof", text: "An update is ready.")) : nil
            let call = RealtimeCall(
                provider: provider,
                voice: environment["FLEET_COMMS_REALTIME_PROOF_VOICE"] ?? (provider == .grok ? "rex" : "marin"),
                source: .wav(URL(fileURLWithPath: wav)),
                silenceSeconds: 0.8, idleHangUp: 5, outreach: outreach, dataDirectory: URL(fileURLWithPath: data)
            ) { RealtimePrompt.instructions(fleetSummary: nil, refreshedAt: nil) }
            let delegate = RealtimeLookupDelegate()
            call.observeToolCall = { name, arguments in
                delegate.toolCalls.append(["name": name, "arguments": arguments])
            }
            call.delegate = delegate
            defer { call.end() }
            call.start()
            let deadline = Date().addingTimeInterval(60)
            while !call.ended, Date() < deadline {
                try await Task.sleep(for: .milliseconds(100))
            }
            let completed = call.ended
            call.end(reason: "proof_timeout")
            try delegate.writeProof(to: URL(fileURLWithPath: root), lane: provider.id, completed: completed)
            #expect(completed)
            #expect(delegate.failure == nil)
            #expect(delegate.heardAudio)
            #expect(delegate.handoffs.isEmpty)
            #expect(delegate.toolCalls.contains { $0["name"] == RealtimePrompt.lookupToolName })
            #expect(delegate.answer.contains(expectedFolder))
            #expect(outreach?.completed ?? true)
        }
    }

    @Suite(
        .serialized,
        .enabled(if: ProcessInfo.processInfo.environment["FLEET_COMMS_REPLY_ROUTING_PROOF_ROOT"] != nil)
    )
    @MainActor
    struct RealtimeReplyProofTests {
        @Test(arguments: [false, true])
        func selectedEchoReadsBothReplyTypes(requested: Bool) async throws {
            let environment = ProcessInfo.processInfo.environment
            let root = try URL(fileURLWithPath: #require(environment["FLEET_COMMS_REPLY_ROUTING_PROOF_ROOT"]))
            let wav = try #require(environment["FLEET_COMMS_OUTREACH_PROOF_WAV"])
            try #require(Bundle.main.bundleIdentifier?.hasPrefix("com.fleetcomms.proof.") == true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let name = "realtime-reply-proof-\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: name))
            defaults.set(true, forKey: AppSettings.Key.fluidSpeechProAdopted)
            defaults.set("", forKey: AppSettings.Key.firstmateHome)
            let settings = AppSettings(defaults: defaults)
            settings.assistantEnabled = false
            settings.voiceLane = .chatGPTRealtime
            settings.outreachVoice = .gptRealtime
            settings.setRealtimeEnabled(true, for: .chatGPT)
            settings.setRealtimeVoice("echo", for: .chatGPT)
            let model = AppModel(settings: settings)
            model.outreachSourceOverride = .wav(URL(fileURLWithPath: wav))
            defer { model.endCallQuietly(); defaults.removePersistentDomain(forName: name) }
            if requested {
                model.receive(.init(noteID: "requested-proof", body: "An update is ready.", seenAt: Date()))
            } else {
                model.receiveSessionReply(.init(id: "outreach-proof", text: "An update is ready."))
            }
            try await checkReading(model, root: root, requested: requested)
        }

        private func checkReading(_ model: AppModel, root: URL, requested: Bool) async throws {
            let call = try #require(model.call)
            let reading = try #require(call.outreach)
            let deadline = Date().addingTimeInterval(30)
            var speaking = false
            while !call.ended, !reading.completed, Date() < deadline {
                speaking = speaking || model.state == .call(.speaking)
                try await Task.sleep(for: .milliseconds(50))
            }
            let result = "requested=\(requested) voice=\(call.voice) lane=\(call.provider.id) " +
                "speaking=\(speaking) completed=\(reading.completed) local_voice_loaded=\(model.speaker.isLoaded)\n"
            try result.write(
                to: root.appendingPathComponent("\(requested ? "requested" : "outreach")-audio.txt"),
                atomically: true, encoding: .utf8
            )
            try reading.transcript.write(
                to: root.appendingPathComponent("\(requested ? "requested" : "outreach")-transcript.txt"),
                atomically: true, encoding: .utf8
            )
            #expect(reading.completed)
            #expect(speaking)
            #expect(call.voice == "echo")
            #expect(call.provider == .chatGPT)
            #expect(!model.speaker.isLoaded)
            #expect(OutreachWire.matches(reading.transcript, text: "An update is ready."))
            call.end(.offline)
            try await captureFailure(model, root: root, requested: requested)
        }

        fileprivate func captureFailure(_ model: AppModel, root: URL, requested: Bool) async throws {
            for dark in [false, true] {
                let window = NSWindow(
                    contentRect: NSRect(x: 100, y: 100, width: 520, height: 500),
                    styleMask: [.titled], backing: .buffered, defer: false
                )
                window.title = "Realtime reply proof"
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                window.contentView = NSHostingView(rootView: ExpandedContent(model: model)
                    .environment(\.notchScale, TextSizeChoice.largest.scale)
                    .environment(\.colorScheme, dark ? .dark : .light)
                    .padding(24).frame(width: 520, height: 500, alignment: .topLeading)
                    .background(Color.black).foregroundStyle(.white))
                window.makeKeyAndOrderFront(nil)
                try await Task.sleep(for: .milliseconds(800))
                window.contentView?.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
                UICapture.write(window, to: root.appendingPathComponent(
                    "\(requested ? "requested" : "outreach")-error-\(dark ? "dark" : "light").png"
                ))
                window.orderOut(nil)
            }
        }
    }

    @Suite(.enabled(if: ProcessInfo.processInfo.environment["FLEET_COMMS_REPLY_ROUTING_PROOF_ROOT"] != nil))
    @MainActor
    struct RealtimeReplyUIProofTests {
        @Test func visibleFailureNoticeRenders() async throws {
            let path = try #require(ProcessInfo.processInfo.environment["FLEET_COMMS_REPLY_ROUTING_PROOF_ROOT"])
            let name = "realtime-reply-ui-proof-\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: name))
            defaults.set(true, forKey: AppSettings.Key.fluidSpeechProAdopted)
            defaults.set("", forKey: AppSettings.Key.firstmateHome)
            let settings = AppSettings(defaults: defaults)
            settings.voiceLane = .chatGPTRealtime
            let model = AppModel(settings: settings)
            defer { model.endCallQuietly(); defaults.removePersistentDomain(forName: name) }
            model.receive(.init(noteID: "ui-proof", body: "An update is ready.", seenAt: Date()))
            let call = try #require(model.call)
            call.end(.offline)
            try await RealtimeReplyProofTests().captureFailure(model, root: URL(fileURLWithPath: path), requested: true)
        }
    }

    private extension RealtimeLookupDelegate {
        func writeProof(to folder: URL, lane: String, completed: Bool) throws {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let result = "lane=\(lane) completed=\(completed) audio=\(heardAudio) " +
                "handoffs=\(handoffs.count) error=\(failure?.code ?? "none")\n\(answer)\n"
            try result.write(to: folder.appendingPathComponent("\(lane)-answer.txt"), atomically: true, encoding: .utf8)
            try JSONSerialization.data(withJSONObject: toolCalls, options: [.prettyPrinted, .sortedKeys])
                .write(to: folder.appendingPathComponent("\(lane)-tool-calls.json"))
        }
    }
#endif
