//  SpeechScrollProofTests.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/29/26.

import AppKit
import Foundation
@testable import NotchVoice
import Testing

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["FLEET_COMMS_TRANSCRIPT_PROOF_ROOT"] != nil))
@MainActor
struct SpeechScrollProofTests {
    @Test func spokenReplyFollowsPlaybackAndResetsForTheNextReply() async throws {
        let fixture = try SpeechScrollFixture()
        defer { fixture.close() }
        let root = try URL(fileURLWithPath: #require(
            ProcessInfo.processInfo.environment["FLEET_COMMS_TRANSCRIPT_PROOF_ROOT"]
        ))
        let text = SpeechScrollFixture.text
        fixture.model.state = .reply(text: text, speaking: true, from: .firstMate)
        for round in 1 ... 2 {
            let id = UUID()
            fixture.model.speechPlayback = .init(id: id, text: text, utf16Offset: 0)
            try await settle()
            var scroll = try #require(fixture.scroll)
            #expect(abs(scroll.contentView.bounds.origin.y) < 1)
            fixture.capture("paced-\(round)-start", root: root)
            fixture.model.speechPlayback = .init(
                id: id, text: text, utf16Offset: (text as NSString).range(of: "Passage 7").location
            )
            try await settle()
            scroll = try #require(fixture.scroll)
            let middle = scroll.contentView.bounds.origin.y
            #expect(middle > 100)
            fixture.capture("paced-\(round)-middle", root: root)
            fixture.model.speechPlayback = .init(id: id, text: text, utf16Offset: text.utf16.count)
            try await settle()
            #expect(scroll.contentView.bounds.origin.y > middle)
            fixture.capture("paced-\(round)-end", root: root)
        }
    }

    @Test func manualScrollingPausesSpeechFollow() async throws {
        let fixture = try SpeechScrollFixture()
        defer { fixture.close() }
        let text = SpeechScrollFixture.text
        let id = UUID()
        fixture.model.state = .reply(text: text, speaking: true, from: .firstMate)
        fixture.model.speechPlayback = .init(id: id, text: text, utf16Offset: text.utf16.count / 2)
        try await settle()
        let scroll = try #require(fixture.scroll)
        try scrollManually(scroll)
        try await settle()
        let paused = scroll.contentView.bounds.origin.y
        fixture.model.speechPlayback = .init(id: id, text: text, utf16Offset: text.utf16.count)
        try await settle()
        #expect(abs(scroll.contentView.bounds.origin.y - paused) < 1)
    }

    private func scrollManually(_ scroll: NSScrollView) throws {
        for phase in [CGScrollPhase.began, .changed, .ended] {
            let event = try #require(CGEvent(
                scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 60, wheel2: 0, wheel3: 0
            ))
            event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            event.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue))
            try scroll.scrollWheel(with: #require(NSEvent(cgEvent: event)))
        }
    }

    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(750))
    }
}
