//  ReplySpeaker.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

@preconcurrency import AVFoundation
import FluidAudio
import Foundation

/// Kokoro (on-device, ANE) text-to-speech with stop-on-demand for barge-in.
/// Each sentence is synthesized and queued on its own, so audio starts after the
/// first sentence while the next ones are synthesized during playback.
@MainActor
final class ReplySpeaker {
    private var kokoro: KokoroAneManager?
    private var engine: AVAudioEngine?
    private var speakTask: Task<Void, Never>?
    private var onFinish: (() -> Void)?
    private var generation = 0
    private var progressTask: Task<Void, Never>?

    var onProgress: ((SpeechPlayback?) -> Void)?

    var speed: () -> SpeechSpeed = { .brisk }

    var isLoaded: Bool {
        kokoro != nil
    }

    var isSpeaking: Bool {
        onFinish != nil
    }

    func load(voiceID: String, progress: @escaping ModelStore.Progress = { _, _ in }) async throws {
        try await ModelStore.downloadVoice(voiceID, root: ModelLoader.modelsRoot, progress: progress)
        let manager = KokoroAneManager(
            defaultVoice: voiceID,
            directory: LocalModel.kokoro.hubDirectory(root: ModelLoader.modelsRoot)
        )
        try await manager.initialize(preloadVoices: [voiceID])
        // The first synthesis pays a one-off warm-up; pay it now, not on the first reply.
        _ = try await manager.synthesizeDetailed(text: "Ready.")
        kokoro = manager
    }

    func setVoice(_ voiceID: String, progress: @escaping ModelStore.Progress = { _, _ in }) async throws {
        guard let kokoro else { return try await load(voiceID: voiceID, progress: progress) }
        try await ModelStore.downloadVoice(voiceID, root: ModelLoader.modelsRoot, progress: progress)
        _ = try await kokoro.synthesizeDetailed(text: "Ready.", voice: voiceID)
        await kokoro.setDefaultVoice(voiceID)
    }

    /// Speaks `text`; `onStart` fires when audio begins, `onFinish` when it ends or is stopped.
    func speak(_ text: String, onStart: @escaping () -> Void, onFinish: @escaping () -> Void) {
        stop()
        guard let kokoro, !text.isEmpty else { return onFinish() }
        self.onFinish = onFinish
        generation += 1
        let current = generation
        let parts = Self.parts(of: text)
        let playbackID = UUID()
        onProgress?(SpeechPlayback(id: playbackID, text: parts.joined(separator: " "), utf16Offset: 0))
        EventLog.record("speech_queued", [
            "speech_id": String(current), "parts": String(parts.count), "characters": String(text.count)
        ])
        speakTask = Task {
            do {
                try await play(parts, with: kokoro, generation: current, playbackID: playbackID, onStart: onStart)
            } catch is CancellationError {
                return
            } catch {
                Log.speech.error("Speech failed: \(error.localizedDescription, privacy: .public)")
                finish(generation: current)
            }
        }
    }

    func stop() {
        speakTask?.cancel()
        speakTask = nil
        progressTask?.cancel()
        progressTask = nil
        engine?.stop()
        engine = nil
        finish(generation: generation)
    }

    private func play(
        _ parts: [String], with kokoro: KokoroAneManager, generation: Int, playbackID: UUID, onStart: () -> Void
    ) async throws {
        let (player, format) = try makePlayer()
        var prepared: (result: KokoroAneSynthesisResult, speed: SpeechSpeed)?
        let text = parts.joined(separator: " ")
        var characterOffset = 0
        for (index, part) in parts.enumerated() {
            let result = try await synthesize(part, with: kokoro, prepared: prepared)
            try Task.checkCancellation()
            let frameOffset = player.lastRenderTime.flatMap { player.playerTime(forNodeTime: $0) }?.sampleTime ?? 0
            let played = Self.enqueue(result.samples, on: player, format: format)
            if index == 0 {
                try player.playAudio()
                onStart()
            }
            trackProgress(
                player: player, playback: SpeechPlayback(id: playbackID, text: text, utf16Offset: characterOffset),
                characters: characterOffset ..< characterOffset + part.utf16.count,
                frames: frameOffset ..< frameOffset + Int64(result.samples.count), generation: generation
            )
            if index + 1 < parts.count {
                let nextSpeed = speed()
                prepared = try await (
                    kokoro.synthesizeDetailed(text: parts[index + 1], speed: nextSpeed.rawValue),
                    nextSpeed
                )
            }
            for await _ in played {
                break
            }
            try Task.checkCancellation()
            progressTask?.cancel()
            characterOffset += part.utf16.count + 1
            onProgress?(SpeechPlayback(id: playbackID, text: text, utf16Offset: characterOffset - 1))
            EventLog.record("speech_part_played", [
                "speech_id": String(generation), "part": String(index + 1),
                "parts": String(parts.count), "characters": String(part.count)
            ])
        }
        finish(generation: generation)
    }

    private func synthesize(
        _ part: String, with kokoro: KokoroAneManager, prepared: (result: KokoroAneSynthesisResult, speed: SpeechSpeed)?
    ) async throws -> KokoroAneSynthesisResult {
        let chosen = speed()
        if let prepared, prepared.speed == chosen {
            return prepared.result
        }
        return try await kokoro.synthesizeDetailed(text: part, speed: chosen.rawValue)
    }

    private func makePlayer() throws -> (AVAudioPlayerNode, AVAudioFormat) {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
        engine.attach(player)
        try engine.connectNode(player, to: engine.mainMixerNode, format: format)
        try engine.start()
        self.engine = engine
        return (player, format)
    }

    private func trackProgress(
        player: AVAudioPlayerNode, playback: SpeechPlayback, characters: Range<Int>, frames: Range<Int64>,
        generation current: Int
    ) {
        progressTask?.cancel()
        guard onProgress != nil else { return }
        progressTask = Task { [weak self] in
            while !Task.isCancelled, let self, generation == current, isSpeaking {
                if let render = player.lastRenderTime, let time = player.playerTime(forNodeTime: render) {
                    let fraction = min(
                        1,
                        max(0, Double(time.sampleTime - frames.lowerBound) / Double(max(1, frames.count)))
                    )
                    let offset = characters.lowerBound + Int(Double(characters.count) * fraction)
                    onProgress?(SpeechPlayback(id: playback.id, text: playback.text, utf16Offset: offset))
                }
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            }
        }
    }

    private static func enqueue(
        _ samples: [Float], on player: AVAudioPlayerNode, format: AVAudioFormat
    ) -> AsyncStream<Void> {
        let (played, continuation) = AsyncStream.makeStream(of: Void.self)
        guard let buffer = buffer(samples.isEmpty ? [0] : samples, format: format) else {
            continuation.finish()
            return played
        }
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in
            continuation.yield(())
            continuation.finish()
        }
        return played
    }

    private func finish(generation finished: Int) {
        guard finished == generation, let callback = onFinish else { return }
        onFinish = nil
        progressTask?.cancel()
        progressTask = nil
        onProgress?(nil)
        engine?.stop()
        engine = nil
        callback()
    }

    nonisolated static func parts(of text: String) -> [String] {
        let sentences = SpokenSummary.splitSentences(text)
        return sentences.isEmpty ? [text] : sentences
    }

    private static func buffer(_ samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        return buffer
    }
}
