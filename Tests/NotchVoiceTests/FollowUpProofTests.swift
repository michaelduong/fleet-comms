//  FollowUpProofTests.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import FluidAudio
import Foundation
@testable import NotchVoice
import Testing

@Suite(.serialized, .enabled(if: AudioProofSupport.isEnabled))
@MainActor
struct FollowUpProofTests {
    @Test func unsolicitedReplyAcceptsSpeechInsideTheReplyWindow() async throws {
        let (model, cleanup) = try await makeModel()
        defer {
            model.dismiss()
            cleanup()
        }
        let kokoro = KokoroAneManager(
            directory: ModelLoader.modelsRoot.appendingPathComponent("TTS", isDirectory: true)
        )
        try await kokoro.initialize(preloadVoices: [VoiceChoice.defaultID])
        let words = try await kokoro.synthesizeDetailed(text: "Please repeat that summary.")
        let delayed = [Float](repeating: 0, count: 24000 * 3 + 12000) + words.samples
        let spoken = try AudioProofSupport.writeWav(delayed, name: "outreach-follow-up.wav")
        try await checkSpokenFollowUp(model, url: spoken, outreach: true)
    }

    @Test func unsolicitedReplyKeepsItsReplyWindowAndDismissesWhileHovered() async throws {
        let (model, cleanup) = try await makeModel()
        defer {
            model.dismiss()
            cleanup()
        }
        let silence = try AudioProofSupport.writeWav(
            [Float](repeating: 0, count: 24000 * 10),
            name: "outreach-quiet.wav"
        )
        var opened: Date?
        model.followUpFeed = { opened = Date(); return WavFileFeed(url: silence) }
        model.receiveSessionReply(.init(id: "quiet-outreach", text: "An update is ready."))
        model.setPillHovered(true)
        try await AudioProofSupport.eventually { model.isFollowUp }
        #expect(!model.speaker.isSpeaking)
        #expect(model.state == .listening)
        try await Task.sleep(for: .seconds(1))
        #expect(model.isFollowUp)
        try await AudioProofSupport.eventually(seconds: 6) { model.state == .idle }
        let elapsed = try Date().timeIntervalSince(#require(opened))
        #expect(model.feed == nil)
        #expect(elapsed >= 5 && elapsed < 5.5)
        try AudioProofSupport.record("outreach_silence_hovered_ms=\(Int(elapsed * 1000)) state=idle")
    }

    @Test func realtimeLaneReplyStillOpensTheWindowAndAPendingQuestionWaitsForIt() async throws {
        let (model, cleanup) = try await makeModel()
        model.settings.voiceLane = .grokVoice
        model.startQuestions()
        let folder = try AskQuestionFixture.publish(in: AudioProofSupport.root)
        defer {
            model.stopQuestions()
            try? FileManager.default.removeItem(at: folder)
            cleanup()
        }
        model.questions.poll()
        #expect(model.displayState == .question)
        let silence = try AudioProofSupport.writeWav([Float](repeating: 0, count: 24000 * 10), name: "lane-quiet.wav")
        try await checkQuietWindow(model, url: silence)
        #expect(model.displayState == .question)
        try AudioProofSupport.record("realtime_lane_reply_window=passed question_waited=passed")
    }

    @Test func wavFollowUpSilenceAndCancellation() async throws {
        let (model, cleanup) = try await makeModel()
        defer {
            model.cancelListeningSession()
            model.speaker.stop()
            cleanup()
        }
        let kokoro = KokoroAneManager(
            directory: ModelLoader.modelsRoot.appendingPathComponent("TTS", isDirectory: true)
        )
        try await kokoro.initialize(preloadVoices: [VoiceChoice.defaultID])
        let words = try await kokoro.synthesizeDetailed(text: "Please repeat that summary.")
        let delayed = [Float](repeating: 0, count: 24000 * 3 + 12000) + words.samples
        let spoken = try AudioProofSupport.writeWav(delayed, name: "follow-up.wav")
        let silence = try AudioProofSupport.writeWav([Float](repeating: 0, count: 24000 * 10), name: "silence.wav")
        try await checkSpokenFollowUp(model, url: spoken)
        try await checkQuietWindow(model, url: silence)
        try await checkCancellation(model, url: silence)
        try await checkRejectedSounds(model, speech: words.samples)
    }

    private func makeModel() async throws -> (AppModel, () -> Void) {
        let name = "NotchVoice.follow-up.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        let settings = AppSettings(defaults: defaults)
        settings.assistantEnabled = false
        settings.speechModel = .parakeetRealtime320
        settings.autoDismissSeconds = 5
        settings.firstmateHome = AudioProofSupport.root.path
        settings.inboxScript = AudioProofSupport.root.appendingPathComponent("fake-inbox.sh").path
        let script = """
        #!/bin/sh
        if [ "$1" = note ]; then
            echo called > "$FM_HOME/note-called"
            echo '{"outcome":"announced","id":"speech-proof"}'
        else
            echo '{"replies":[],"reply_cursor":""}'
        fi
        """
        try script.write(toFile: settings.inboxScript, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: settings.inboxScript)
        let model = AppModel(settings: settings)
        model.vad = try await ModelLoader.loadVad(progress: { _ in })
        model.recognizer = try await ModelLoader.loadRecognizer(
            .parakeetRealtime320,
            silenceSeconds: 0.8,
            progress: { _ in }
        )
        try await model.speaker.load(voiceID: VoiceChoice.defaultID)
        return (model, { defaults.removePersistentDomain(forName: name) })
    }

    private func checkSpokenFollowUp(_ model: AppModel, url: URL, outreach: Bool = false) async throws {
        let marker = AudioProofSupport.root.appendingPathComponent("note-called")
        try? FileManager.default.removeItem(at: marker)
        var openedAfterPlayback = false
        var opened = Date()
        model.followUpFeed = {
            opened = Date()
            openedAfterPlayback = !model.speaker.isSpeaking
            return WavFileFeed(url: url)
        }
        if outreach {
            model.receiveSessionReply(.init(id: "spoken-outreach", text: "Ready for your next question."))
        } else {
            model.receive(.init(noteID: "proof", body: "Ready for your next question.", seenAt: Date()))
        }
        #expect(model.feed == nil)
        try await AudioProofSupport.eventually(seconds: 20) { FileManager.default.fileExists(atPath: marker.path) }
        try await AudioProofSupport.eventually { model.state == .waiting }
        #expect(openedAfterPlayback)
        #expect(model.feed == nil)
        #expect(!model.transcript.isEmpty)
        #expect(Date().timeIntervalSince(opened) > 5)
        try AudioProofSupport.record("follow_up_wav=passed note_routed_without_hotkey=passed playback_overlap=none")
    }

    private func checkQuietWindow(_ model: AppModel, url: URL) async throws {
        var opened: Date?
        model.followUpFeed = { opened = Date(); return WavFileFeed(url: url) }
        model.receive(.init(noteID: "quiet", body: "Ready.", seenAt: Date()))
        try await AudioProofSupport.eventually { model.isFollowUp }
        #expect(model.state == .listening)
        try await AudioProofSupport.eventually(seconds: 7) { model.state == .idle }
        let elapsed = try Date().timeIntervalSince(#require(opened))
        #expect(model.feed == nil)
        #expect(!model.isFollowUp)
        #expect(elapsed >= 5 && elapsed < 5.5)
        try AudioProofSupport.record("silence_feed_off_ms=\(Int(elapsed * 1000)) state=idle")
    }

    private func checkCancellation(_ model: AppModel, url: URL) async throws {
        model.followUpFeed = { WavFileFeed(url: url) }
        for escape in [true, false] {
            model.state = .reply(text: "Ready.", speaking: false, from: .assistant)
            model.scheduleFollowUp()
            try await AudioProofSupport.eventually { model.isFollowUp }
            if escape {
                model.escapePressed()
            } else {
                model.talkPressed()
            }
            #expect(model.state == .idle)
            #expect(model.feed == nil)
        }
        model.settings.keepListeningAfterReply = false
        model.scheduleFollowUp()
        try await Task.sleep(for: .milliseconds(50))
        #expect(model.feed == nil)
        model.settings.keepListeningAfterReply = true
        model.settings.autoDismissSeconds = 0
        model.scheduleFollowUp()
        try await Task.sleep(for: .milliseconds(50))
        #expect(model.feed == nil)
        try AudioProofSupport
            .record("escape=passed hotkey=passed toggle_off=passed never_dismiss_no_passive_mic=passed")
    }

    private func checkRejectedSounds(_ model: AppModel, speech: [Float]) async throws {
        let marker = AudioProofSupport.root.appendingPathComponent("note-called")
        let noise = (0 ..< 144_000).map {
            Float(sin(Double($0) * 0.13) * 0.04 + sin(Double($0) * 0.031) * 0.03)
        }
        let fixtures = [("room-noise", noise), ("short-speech", Array(speech.prefix(4800)))]
        for (name, samples) in fixtures {
            try? FileManager.default.removeItem(at: marker)
            let url = try AudioProofSupport.writeWav(samples, name: name + ".wav")
            model.settings.autoDismissSeconds = 5
            model.followUpFeed = { WavFileFeed(url: url) }
            model.state = .reply(text: "Ready.", speaking: false, from: .assistant)
            model.scheduleFollowUp()
            try await AudioProofSupport.eventually { model.isFollowUp }
            try await AudioProofSupport.eventually(seconds: 7) { model.state == .idle }
            #expect(!FileManager.default.fileExists(atPath: marker.path))
            #expect(model.feed == nil)
            try AudioProofSupport.record("\(name)_no_send=passed")
        }
    }
}
