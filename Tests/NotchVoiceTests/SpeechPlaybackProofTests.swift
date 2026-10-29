//  SpeechPlaybackProofTests.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import FluidAudio
import Foundation
@testable import NotchVoice
import Synchronization
import Testing

@Suite(.serialized, .enabled(if: AudioProofSupport.isEnabled))
@MainActor
struct SpeechPlaybackProofTests {
    @Test func additionalEnglishMaleVoices() async throws {
        UserDefaults.standard
            .register(defaults: ["modelsRoot": AudioProofSupport.root.appendingPathComponent("models").path])
        ModelPins.apply()
        let speaker = ReplySpeaker()
        speaker.speed = { .normal }
        let updates = Mutex<[String]>([])
        let progress: ModelStore.Progress = { fraction, activity in
            updates.withLock { $0.append("\(fraction.map(String.init(describing:)) ?? "indeterminate") \(activity)") }
        }
        let kokoro = KokoroAneManager(directory: ModelLoader.modelsRoot.appendingPathComponent("TTS"))
        for voice in ["am_echo", "am_liam", "bm_daniel"] {
            try await speaker.setVoice(voice, progress: progress)
            let text = "The update is ready. You can review the changes now."
            var started = false
            var finished = false
            speaker.speak(text, onStart: { started = true }, onFinish: { finished = true })
            try await AudioProofSupport.eventually(seconds: 45) { finished }
            #expect(started)
            if voice == "am_echo" {
                try await kokoro.initialize()
            }
            let result = try await kokoro.synthesizeDetailed(text: text, voice: voice)
            let allFinite = result.samples.allSatisfy(\.isFinite)
            #expect(allFinite)
            #expect(result.samples.contains { abs($0) > 0.01 })
            _ = try AudioProofSupport.writeWav(result.samples, name: voice + ".wav")
            try AudioProofSupport
                .record(
                    "voice=\(voice) playback_started=\(started) playback_finished=\(finished) "
                        + "samples=\(result.samples.count)"
                )
        }
        for update in updates.withLock({ $0 }) {
            try AudioProofSupport.record(update)
        }
    }

    @Test func nativeSpeedTimingAndBargeIn() async throws {
        let speaker = ReplySpeaker()
        try await speaker.load(voiceID: VoiceChoice.defaultID)
        let reply = "The update is ready. You can review the changes now. "
            + "Let me know if you would like another summary."
        for round in 1 ... 3 {
            for speed in [SpeechSpeed.normal, .brisk, .fast, .double] {
                speaker.speed = { speed }
                var first: Date?
                var ended = false
                let began = Date()
                speaker.speak(reply, onStart: { first = Date() }, onFinish: { ended = true })
                try await AudioProofSupport.eventually(seconds: 30) { ended }
                let start = try #require(first)
                try AudioProofSupport.record(
                    "round=\(round) speed=\(speed.title) first_ms=\(Int(start.timeIntervalSince(began) * 1000)) "
                        + "playback_ms=\(Int(Date().timeIntervalSince(start) * 1000))"
                )
            }
        }
        try await checkLiveSpeedChange(speaker, reply: reply)
        try await checkBargeIn(speaker, reply: reply)
    }

    private func checkBargeIn(_ speaker: ReplySpeaker, reply: String) async throws {
        var cancelledStarts = 0
        var cancelledFinishes = 0
        speaker.speak(reply, onStart: { cancelledStarts += 1 }, onFinish: { cancelledFinishes += 1 })
        speaker.stop()
        try await Task.sleep(for: .milliseconds(300))
        #expect(cancelledStarts == 0)
        #expect(cancelledFinishes == 1)
        var finishes = 0
        var started = false
        speaker.speak(reply, onStart: { started = true }, onFinish: { finishes += 1 })
        try await AudioProofSupport.eventually { started }
        speaker.stop()
        #expect(!speaker.isSpeaking)
        #expect(finishes == 1)
        var replacementEnded = false
        speaker.speak("Ready.", onStart: {}, onFinish: { replacementEnded = true })
        try await AudioProofSupport.eventually { replacementEnded }
        #expect(finishes == 1)
        try AudioProofSupport.record("barge_in=passed replacement=passed")
    }

    private func checkLiveSpeedChange(_ speaker: ReplySpeaker, reply: String) async throws {
        var chosen = SpeechSpeed.normal
        speaker.speed = { chosen }
        var started: Date?
        var finished = false
        speaker.speak(reply, onStart: { started = Date() }, onFinish: { finished = true })
        try await AudioProofSupport.eventually { started != nil }
        try await Task.sleep(for: .milliseconds(600))
        chosen = .double
        try await AudioProofSupport.eventually { finished }
        let elapsed = try Date().timeIntervalSince(#require(started))
        #expect(elapsed < 6.5)
        try AudioProofSupport.record("next_sentence_speed_change=passed playback_ms=\(Int(elapsed * 1000))")
    }
}
