//  TranscriptProofTests.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import AppKit
@testable import NotchVoice
import Observation
import SwiftUI
import Testing

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["FLEET_COMMS_TRANSCRIPT_PROOF_ROOT"] != nil))
@MainActor
struct TranscriptProofTests {
    @Observable final class Content {
        var speaking = true
        var text = (1 ... 25)
            .map { "Update \($0). The work is ready for review, with full details preserved on screen." }
            .joined(separator: "\n\n")
    }

    @Test func transcriptRendersAndScrolls() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["FLEET_COMMS_TRANSCRIPT_PROOF_ROOT"])
        let root = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for appearance in ["light", "dark"] {
            try await checkTranscript(appearance: appearance, root: root)
        }
    }

    private func checkTranscript(appearance: String, root: URL) async throws {
        let content = Content()
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 440, height: 370),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.title = "Transcript proof"
        window.appearance = NSAppearance(named: appearance == "light" ? .aqua : .darkAqua)
        let host = NSHostingView(rootView: TranscriptFixture(content: content))
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        try await settle()
        var scroll = try #require(findScroll(in: host))
        #expect(scroll.documentView!.bounds.height > scroll.contentView.bounds.height)
        UICapture.write(window, to: root.appendingPathComponent("reply-\(appearance)-opening.png"))
        #expect(abs(scroll.contentView.bounds.origin.y) < 1)
        content.text += "\n\nAdditional reply details arrive. " + String(
            repeating: "More details. ",
            count: 20
        )
        try await settle()
        scroll = try #require(findScroll(in: host))
        #expect(abs(scroll.contentView.bounds.origin.y) < 1)
        content.speaking = false
        try await settle()
        #expect(abs(scroll.contentView.bounds.origin.y) < 1)
        let bottom = scroll.documentView!.bounds.height - scroll.contentView.bounds.height
        scroll.contentView.scroll(to: NSPoint(x: 0, y: bottom))
        scroll.reflectScrolledClipView(scroll.contentView)
        try await settle()
        #expect(scroll.contentView.bounds.origin.y > 100)
        content.text = "A different reply starts here.\n\n" + content.text
        content.speaking = true
        try await settle()
        scroll = try #require(findScroll(in: host))
        UICapture.write(window, to: root.appendingPathComponent("transcript-\(appearance)-start.png"))
        #expect(abs(scroll.contentView.bounds.origin.y) < 1)
    }

    @Test func liveTranscriptStillFollowsLatest() async throws {
        let content = Content()
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 440, height: 370),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        let host = NSHostingView(rootView: LiveTranscriptFixture(content: content))
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        try await settle()
        let scroll = try #require(findScroll(in: host))
        let initial = scroll.contentView.bounds.origin.y
        #expect(initial > 100)
        content.text += String(repeating: " More live transcription.", count: 100)
        try await settle()
        #expect(scroll.contentView.bounds.origin.y > initial)
    }

    @Test(arguments: [RealtimeProvider.grok, .chatGPT])
    func consecutiveOutreachRepliesStartAtTop(provider: RealtimeProvider) async throws {
        let path = try #require(ProcessInfo.processInfo.environment["FLEET_COMMS_TRANSCRIPT_PROOF_ROOT"])
        let name = "transcript-proof-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: AppSettings.Key.fluidSpeechProAdopted)
        defaults.set("", forKey: AppSettings.Key.firstmateHome)
        let model = AppModel(settings: AppSettings(defaults: defaults))
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 440, height: 370),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        let host = NSHostingView(rootView: ExpandedContent(model: model).padding(18))
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        for index in 1 ... 2 {
            let text = "Reply \(index).\n\n" + Content().text
            let reading = RealtimeOutreach(reply: .init(id: "proof-\(index)", text: text))
            let call = RealtimeCall(
                provider: provider, voice: "", source: .wav(URL(fileURLWithPath: "/unused")),
                silenceSeconds: 0.8, outreach: reading
            ) { "" }
            model.call = call
            model.call(call, phase: .connecting)
            model.call(call, text: text)
            try await checkOutreachOpening(model: model, call: call, host: host)
            UICapture.write(
                window,
                to: URL(fileURLWithPath: path)
                    .appendingPathComponent("outreach-\(provider.id)-\(index)-start.png")
            )
            try await scrollToBottom(host: host)
            try await checkOutreachConversation(model: model, call: call, host: host)
        }
    }

    private func checkOutreachOpening(model: AppModel, call: RealtimeCall, host: NSView) async throws {
        try await settle()
        var scroll = try #require(findScroll(in: host))
        #expect(scroll.documentView!.bounds.height > scroll.contentView.bounds.height)
        #expect(abs(scroll.contentView.bounds.origin.y) < 1)
        model.call(call, phase: .speaking)
        try await settle()
        scroll = try #require(findScroll(in: host))
        #expect(abs(scroll.contentView.bounds.origin.y) < 1)
    }

    private func scrollToBottom(host: NSView) async throws {
        let scroll = try #require(findScroll(in: host))
        let bottom = scroll.documentView!.bounds.height - scroll.contentView.bounds.height
        scroll.contentView.scroll(to: NSPoint(x: 0, y: bottom))
        scroll.reflectScrolledClipView(scroll.contentView)
        try await settle()
        #expect(scroll.contentView.bounds.origin.y > 100)
    }

    private func checkOutreachConversation(model: AppModel, call: RealtimeCall, host: NSView) async throws {
        call.outreach?.completed = true
        model.call(call, phase: .listening)
        model.call(call, text: "Follow-up words. " + Content().text)
        try await settle()
        let scroll = try #require(findScroll(in: host))
        let initial = scroll.contentView.bounds.origin.y
        #expect(initial > 100)
        model.call(call, text: model.transcript + String(repeating: " More live transcription.", count: 100))
        try await settle()
        #expect(scroll.contentView.bounds.origin.y > initial)
    }

    private struct LiveTranscriptFixture: View {
        let content: Content

        var body: some View {
            TranscriptScroll(text: content.text, identifier: "proof.live.transcript")
        }
    }

    private func findScroll(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView {
            return scroll
        }
        return view.subviews.compactMap { findScroll(in: $0) }.first
    }

    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(750))
    }

    private struct TranscriptFixture: View {
        let content: Content

        var body: some View {
            ReplyView(text: content.text, speaking: content.speaking, source: .firstMate, onDismiss: {})
                .padding(18).foregroundStyle(.white).background(.black).environment(\.colorScheme, .dark)
        }
    }
}
