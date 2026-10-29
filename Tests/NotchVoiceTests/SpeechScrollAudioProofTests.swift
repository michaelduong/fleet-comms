//  SpeechScrollAudioProofTests.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/29/26.

import AppKit
import FluidAudio
import Foundation
@testable import NotchVoice
import Testing

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["FLEET_COMMS_SPOKEN_AUDIO_PROOF_ROOT"] != nil))
@MainActor
struct SpeechScrollAudioProofTests {
    @Test func longReadingsFollowActualPlayback() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["FLEET_COMMS_SPOKEN_AUDIO_PROOF_ROOT"])
        let root = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        ModelPins.apply()
        try await checkKokoro(root: root)
        let manager = KokoroAneManager(directory: LocalModel.kokoro.hubDirectory(root: ModelLoader.modelsRoot))
        try await manager.initialize(preloadVoices: [VoiceChoice.defaultID])
        let result = try await manager.synthesizeDetailed(text: SpeechScrollFixture.text, speed: 2)
        #expect(result.samples.count > 240_000)
        for provider in [RealtimeProvider.grok, .chatGPT] {
            try await checkBufferedOutreach(provider, samples: result.samples, root: root)
        }
    }

    private func checkKokoro(root: URL) async throws {
        let fixture = try SpeechScrollFixture()
        defer { fixture.close() }
        try await fixture.model.speaker.load(voiceID: VoiceChoice.defaultID)
        fixture.model.speaker.speed = { .double }
        let text = SpeechScrollFixture.text
        fixture.model.state = .reply(text: text, speaking: true, from: .firstMate)
        let spoken = SpokenSummary.whole(from: text)
        var finished = false
        fixture.model.speaker.speak(spoken, onStart: {}, onFinish: { finished = true })
        try await capturePlayback(fixture, label: "kokoro", root: root, finished: { finished })
        #expect(finished)
    }

    private func checkBufferedOutreach(_ provider: RealtimeProvider, samples: [Float], root: URL) async throws {
        let fixture = try SpeechScrollFixture()
        defer { fixture.close() }
        let reading = RealtimeOutreach(reply: .init(id: "synthetic", text: SpeechScrollFixture.text))
        let call = RealtimeCall(
            provider: provider, voice: "", source: .wav(URL(fileURLWithPath: "/unused")),
            silenceSeconds: 0.8, outreach: reading
        ) { "" }
        call.delegate = fixture.model
        fixture.model.call = call
        fixture.model.call(call, phase: .connecting)
        fixture.model.call(call, text: reading.reply.text)
        let started = Date()
        call.startOutputAudio()
        _ = call.handleOutreach(.transcriptDelta(reading.readingText))
        _ = call.handleOutreach(.audioDelta(itemID: "synthetic", audio: RealtimePCM.encode(samples)))
        _ = call.handleOutreach(.responseDone(status: "completed"))
        try await capturePlayback(fixture, label: provider.id, root: root) {
            !call.audioQueued
        }
        let elapsed = Date().timeIntervalSince(started)
        let duration = Double(samples.count) / Double(RealtimeWire.sampleRate)
        #expect(elapsed >= duration - 0.5)
        try "scheduledSeconds=\(duration) drainedSeconds=\(elapsed)\n"
            .write(to: root.appendingPathComponent(provider.id + "-duration.txt"), atomically: true, encoding: .utf8)
        #expect(!call.ended)
    }

    private func capturePlayback(
        _ fixture: SpeechScrollFixture, label: String, root: URL, finished: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(75)
        var positions: [CGFloat] = []
        var fractions: [Double] = []
        let milestones = [0.0, 0.45, 0.9]
        while Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
            if let playback = fixture.model.speechPlayback, positions.count < milestones.count,
               Double(playback.utf16Offset) / Double(max(1, playback.text.utf16.count)) >= milestones[positions.count] {
                let scroll = try #require(fixture.scroll)
                let phase = ["start", "middle", "end"][positions.count]
                positions.append(scroll.contentView.bounds.origin.y)
                fractions.append(Double(playback.utf16Offset) / Double(max(1, playback.text.utf16.count)))
                fixture.capture("\(label)-\(phase)", root: root)
            }
            if finished(), positions.count == milestones.count {
                break
            }
        }
        try #require(finished())
        try #require(positions.count == 3)
        #expect(abs(positions[0]) < 1)
        #expect(positions[1] > 100)
        #expect(positions[2] > positions[1])
        #expect(fractions[0] < 0.05)
        #expect(fractions[1] < 0.75)
        try "start=\(positions[0]) middle=\(positions[1]) end=\(positions[2]) fractions=\(fractions)\n"
            .write(to: root.appendingPathComponent(label + "-offsets.txt"), atomically: true, encoding: .utf8)
    }
}
