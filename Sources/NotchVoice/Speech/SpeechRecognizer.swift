//  SpeechRecognizer.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

@preconcurrency import AVFoundation
import FluidAudio

/// One utterance at a time: `append` 16 kHz mono samples, read the live partial,
/// then `finish` for the final text. `reset` prepares the next utterance.
protocol SpeechRecognizer: Sendable {
    func append(_ samples: [Float]) async throws -> String
    /// True once the model itself has detected end-of-utterance, if it can.
    func endOfUtteranceDetected() async -> Bool
    func finish() async throws -> String
    func reset() async
}

/// Parakeet realtime (EOU 120M): streaming, cache-aware, with an end-of-utterance head.
final class RealtimeParakeetRecognizer: SpeechRecognizer {
    private let manager: StreamingEouAsrManager
    private let eouFlag = ThreadSafeBox(false)

    init(manager: StreamingEouAsrManager) async {
        self.manager = manager
        let flag = eouFlag
        await manager.setEouCallback { _ in flag.value = true }
    }

    func append(_ samples: [Float]) async throws -> String {
        guard let buffer = Self.pcmBuffer(samples) else { return await manager.getPartialTranscript() }
        _ = try await manager.process(audioBuffer: buffer)
        return await manager.getPartialTranscript()
    }

    func endOfUtteranceDetected() async -> Bool {
        eouFlag.value
    }

    func finish() async throws -> String {
        try await manager.finish()
    }

    func reset() async {
        eouFlag.value = false
        await manager.reset()
    }

    static func pcmBuffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        let format = Resampler.targetFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        samples.withUnsafeBufferPointer { source in
            channel.update(from: source.baseAddress!, count: samples.count)
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        return buffer
    }
}

/// Parakeet TDT v2: an offline model, so the live partial re-transcribes the
/// recent audio about twice a second; `finish` transcribes the whole utterance.
actor TdtParakeetRecognizer: SpeechRecognizer {
    private let manager: AsrManager
    private var samples: [Float] = []
    private var partial = ""
    private var samplesAtLastPartial = 0
    private let partialStride = 8000
    private let partialWindow = 16000 * 20

    init(manager: AsrManager) {
        self.manager = manager
    }

    func append(_ newSamples: [Float]) async throws -> String {
        samples += newSamples
        guard samples.count - samplesAtLastPartial >= partialStride else { return partial }
        samplesAtLastPartial = samples.count
        partial = try await transcribe(Array(samples.suffix(partialWindow)))
        return partial
    }

    func endOfUtteranceDetected() async -> Bool {
        false
    }

    func finish() async throws -> String {
        try await transcribe(samples)
    }

    func reset() async {
        samples.removeAll()
        partial = ""
        samplesAtLastPartial = 0
    }

    private func transcribe(_ audio: [Float]) async throws -> String {
        // AsrManager rejects very short clips; pad to one second with silence.
        let padded = audio.count < 16000 ? audio + [Float](repeating: 0, count: 16000 - audio.count) : audio
        var state = TdtDecoderState.make()
        return try await manager.transcribe(padded, decoderState: &state).text
    }
}
