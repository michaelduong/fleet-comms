//  AskQuestionDictationProofTests.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/29/26.

import FluidAudio
import Foundation
@testable import NotchVoice
import Testing

@Suite(.serialized, .enabled(if: AudioProofSupport.isEnabled))
@MainActor
struct AskQuestionDictationProofTests {
    @MainActor
    private final class Heard {
        var text: String?
    }

    @Test func spokenReplyFillsTheDraftWithoutSendingANote() async throws {
        let (model, cleanup) = try await makeModel()
        defer {
            model.cancelListeningSession()
            cleanup()
        }
        let kokoro = KokoroAneManager(
            directory: ModelLoader.modelsRoot.appendingPathComponent("TTS", isDirectory: true)
        )
        try await kokoro.initialize(preloadVoices: [VoiceChoice.defaultID])
        let words = try await kokoro.synthesizeDetailed(text: "Use the native card please.")
        let spoken = try AudioProofSupport.writeWav(
            [Float](repeating: 0, count: 12000) + words.samples, name: "question-reply.wav"
        )
        let marker = AudioProofSupport.root.appendingPathComponent("note-called")
        try? FileManager.default.removeItem(at: marker)
        let heard = Heard()
        model.beginQuestionDictation(feed: WavFileFeed(url: spoken)) { heard.text = $0 }
        #expect(model.state == .listening)
        #expect(model.questionDictation != nil)
        try await AudioProofSupport.eventually(seconds: 20) { heard.text != nil }
        #expect(model.state == .idle)
        #expect(model.questionDictation == nil)
        #expect(model.feed == nil)
        #expect(!FileManager.default.fileExists(atPath: marker.path))
        let text = try #require(heard.text).lowercased()
        #expect(text.contains("native"))
        try AudioProofSupport.record("question_dictation_wav=passed note_sent=no text=\(text)")
    }

    @Test func stoppingDictationDropsTheTranscriptAndReturnsToIdle() async throws {
        let (model, cleanup) = try await makeModel()
        defer { cleanup() }
        let silence = try AudioProofSupport.writeWav(
            [Float](repeating: 0, count: 24000 * 10), name: "question-silence.wav"
        )
        let heard = Heard()
        model.beginQuestionDictation(feed: WavFileFeed(url: silence)) { heard.text = $0 }
        try await AudioProofSupport.eventually { model.state == .listening }
        model.stopQuestionDictation()
        #expect(model.state == .idle)
        #expect(model.questionDictation == nil)
        #expect(model.feed == nil)
        try await Task.sleep(for: .seconds(1))
        #expect(heard.text == nil)
        try AudioProofSupport.record("question_dictation_stop=passed state=idle")
    }

    private func makeModel() async throws -> (AppModel, () -> Void) {
        let name = "NotchVoice.question-dictation.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        let settings = AppSettings(defaults: defaults)
        settings.assistantEnabled = false
        settings.speechModel = .parakeetRealtime320
        settings.firstmateHome = AudioProofSupport.root.path
        settings.inboxScript = AudioProofSupport.root.appendingPathComponent("fake-inbox.sh").path
        let script = """
        #!/bin/sh
        if [ "$1" = note ]; then
            echo called > "$FM_HOME/note-called"
            echo '{"outcome":"announced","id":"question-proof"}'
        else
            echo '{"replies":[],"reply_cursor":""}'
        fi
        """
        try script.write(toFile: settings.inboxScript, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: settings.inboxScript)
        let model = AppModel(settings: settings)
        model.vad = try await ModelLoader.loadVad(progress: { _ in })
        model.recognizer = try await ModelLoader.loadRecognizer(
            .parakeetRealtime320, silenceSeconds: 0.8, progress: { _ in }
        )
        return (model, { defaults.removePersistentDomain(forName: name) })
    }
}
