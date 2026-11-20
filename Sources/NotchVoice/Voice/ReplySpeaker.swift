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
    private var radio: RadioOutput?
    var bypassRadio = false
    private var speakTask: Task<Void, Never>?
    private var onFinish: (() -> Void)?
    private var generation = 0
    private var progressTask: Task<Void, Never>?

    var onProgress: ((SpeechPlayback?) -> Void)?

    var speed: () -> SpeechSpeed = { .brisk }

    /// Set while a phone is connected: speech is rendered for it instead of this Mac's speakers.
    var phone: PhoneSpeechPlayer?

    /// True while a reply is playing on this Mac's speakers; the phone, if connected, is told so.
    private(set) var playingOnMac = false {
        didSet {
            if oldValue != playingOnMac {
                onRouteChange?()
            }
        }
    }

    var onRouteChange: (() -> Void)?

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
                var first = 0
                if let phone, phone.isAvailable {
                    playingOnMac = false
                    do {
                        try await phone.play(
                            parts,
                            with: kokoro,
                            speed: speed().rawValue,
                            id: playbackID,
                            progress: onProgress
                        )
                        return finish(generation: current)
                    } catch let lost as PhoneLinkLost {
                        // The phone went away mid-reply: the Mac says the rest instead of pacing it to nobody.
                        EventLog.record("speech_phone_lost", [
                            "speech_id": String(current), "resume_part": String(lost.resumeAt), "reason": lost.reason
                        ])
                        first = lost.resumeAt
                    } catch is PhoneWakeError {
                        try Task.checkCancellation()
                        // The phone could not be woken: the Mac says the whole reply instead of losing it.
                        EventLog.record("speech_phone_lost", [
                            "speech_id": String(current), "resume_part": "0", "reason": "wake failed"
                        ])
                    }
                }
                try await playOnMac(parts, with: kokoro, generation: current, id: playbackID, from: first, onStart)
            } catch is CancellationError {
                return
            } catch {
                Log.speech.error("Speech failed: \(error.localizedDescription, privacy: .public)")
                finish(generation: current)
            }
        }
    }

    // swiftlint:disable:next function_parameter_count
    private func playOnMac(
        _ parts: [String], with kokoro: KokoroAneManager, generation: Int, id: UUID, from first: Int,
        _ onStart: () -> Void
    ) async throws {
        playingOnMac = true
        defer {
            // An earlier reply unwinding must not clear the flag while a newer one plays on the Mac.
            if generation == self.generation { playingOnMac = false }
        }
        try await play(parts, with: kokoro, generation: generation, playbackID: id, from: first, onStart: onStart)
    }

    func stop() {
        phone?.stop()
        speakTask?.cancel()
        speakTask = nil
        progressTask?.cancel()
        progressTask = nil
        let fade = radio?.cancel() ?? 0
        let stoppingEngine = engine
        engine = nil
        radio = nil
        if fade > 0 {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(fade))
                stoppingEngine?.stop()
            }
        } else {
            stoppingEngine?.stop()
        }
        finish(generation: generation)
    }

    private func play(
        _ parts: [String], with kokoro: KokoroAneManager, generation: Int, playbackID: UUID, from first: Int = 0,
        onStart: () -> Void
    ) async throws {
        let (player, format) = try makePlayer()
        radio?.begin()
        var prepared: (result: KokoroAneSynthesisResult, speed: SpeechSpeed)?
        let text = parts.joined(separator: " ")
        var characterOffset = parts[..<first].reduce(0) { $0 + $1.utf16.count + 1 }
        for (index, part) in parts.enumerated() where index >= first {
            let result = try await synthesize(part, with: kokoro, prepared: prepared)
            try Task.checkCancellation()
            let frameOffset = player.lastRenderTime.flatMap { player.playerTime(forNodeTime: $0) }?.sampleTime ?? 0
            let played = Self.enqueue(result.samples, on: player, format: format)
            if index == first {
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
            recordPart(generation: generation, index: index, parts: parts.count, characters: part.count)
        }
        try await finishTail(generation: generation)
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
        radio = nil
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

private extension ReplySpeaker {
    func makePlayer() throws -> (AVAudioPlayerNode, AVAudioFormat) {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
        engine.attach(player)
        do {
            radio = try RadioOutput(engine: engine, player: player, format: format, bypass: bypassRadio)
        } catch {
            try engine.connectNode(player, to: engine.mainMixerNode, format: format)
        }
        try engine.start()
        self.engine = engine
        return (player, format)
    }

    func trackProgress(
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

    func finishTail(generation: Int) async throws {
        let tail = radio?.finish() ?? 0
        if tail > 0 {
            try await Task.sleep(for: .seconds(tail))
        }
        try Task.checkCancellation()
        finish(generation: generation)
    }

    func recordPart(generation: Int, index: Int, parts: Int, characters: Int) {
        EventLog.record("speech_part_played", [
            "speech_id": String(generation), "part": String(index + 1),
            "parts": String(parts), "characters": String(characters)
        ])
    }
}
