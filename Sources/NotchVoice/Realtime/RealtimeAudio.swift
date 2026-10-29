//  RealtimeAudio.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

@preconcurrency import AVFoundation

/// Mic in and model audio out on one engine. With the mic, Apple's voice processing cancels the
/// model's own voice from the input, so the server's turn detection hears the owner talk over it
/// (barge-in) and not the speakers. Everything runs on one queue: starting input on a Bluetooth
/// headset can block for seconds.
final class RealtimeAudio: @unchecked Sendable {
    static let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: Double(RealtimeWire.sampleRate), channels: 1, interleaved: false
    )!

    private let queue = DispatchQueue(label: "io.github.michaelduong.fleetcomms.realtime-audio")
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var pending = 0
    private var generation = 0
    private var queuedFrames: Int64 = 0
    private var playbackStarted: UInt64?
    private var progressTimer: DispatchSourceTimer?
    private let onProgress: (@Sendable (Double) -> Void)?
    /// Touching `inputNode` creates an input, so a play-only engine never does.
    private var hasInput = false
    private let onDrained: @Sendable () -> Void

    /// `onDrained` fires on the audio queue when the last queued model audio has played.
    init(onProgress: (@Sendable (Double) -> Void)? = nil, onDrained: @escaping @Sendable () -> Void) {
        self.onProgress = onProgress
        self.onDrained = onDrained
    }

    /// `onInput` gets 24 kHz mono samples from the mic; pass nil to play output only (WAV feed).
    func start(onInput: (@Sendable ([Float]) -> Void)?, onFailure: @escaping @Sendable (Error) -> Void) {
        queue.async { [self] in
            do {
                try startOnQueue(onInput: onInput)
            } catch {
                stopOnQueue()
                onFailure(error)
            }
        }
    }

    func play(
        _ samples: [Float], onStart: (@Sendable () -> Void)? = nil,
        onFailure: (@Sendable (Error) -> Void)? = nil
    ) {
        queue.async { [self] in
            guard let player, let buffer = Self.buffer(samples) else {
                onFailure?(RealtimeError.audioFailed)
                return
            }
            pending += 1
            queuedFrames += Int64(samples.count)
            let current = generation
            player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [self] _ in
                queue.async { self.played(generation: current) }
            }
            if !player.isPlaying {
                do {
                    onProgress?(0)
                    try player.playAudio()
                    playbackStarted = DispatchTime.now().uptimeNanoseconds
                    startProgressTimer()
                    onStart?()
                } catch {
                    onFailure?(error)
                }
            }
        }
    }

    /// Drops queued model audio at once: the owner started talking.
    func flush() {
        queue.async { [self] in
            generation += 1
            pending = 0
            queuedFrames = 0
            playbackStarted = nil
            progressTimer?.cancel()
            progressTimer = nil
            player?.stop()
        }
    }

    func stop() {
        queue.async { [self] in stopOnQueue() }
    }

    private func played(generation finished: Int) {
        guard finished == generation, pending > 0 else { return }
        pending -= 1
        if pending == 0 {
            onProgress?(1)
            playbackStarted = nil
            progressTimer?.cancel()
            progressTimer = nil
            onDrained()
        }
    }

    private func startProgressTimer() {
        guard onProgress != nil, progressTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            guard let self, queuedFrames > 0, let playbackStarted, player?.isPlaying == true else { return }
            // Only buffered outreach observes progress, so its complete duration is known before playback.
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - playbackStarted) / 1_000_000_000
            let duration = Double(queuedFrames) / Self.format.sampleRate
            onProgress?(min(1, elapsed / duration))
        }
        progressTimer = timer
        timer.resume()
    }

    private func startOnQueue(onInput: (@Sendable ([Float]) -> Void)?) throws {
        let engine = AVAudioEngine()
        self.engine = engine
        // The player must be connected before voice processing is on; the other way round
        // the engine fails to start (-10875) on macOS 27.
        let player = AVAudioPlayerNode()
        engine.attach(player)
        try engine.connectNode(player, to: engine.mainMixerNode, format: Self.format)
        self.player = player
        if let onInput {
            hasInput = true
            try Self.installInput(on: engine.inputNode, onInput: onInput)
        }
        engine.prepare()
        try engine.start()
    }

    private static func installInput(
        on input: AVAudioInputNode, onInput: @escaping @Sendable ([Float]) -> Void
    ) throws {
        try input.setVoiceProcessingEnabled(true)
        input.voiceProcessingOtherAudioDuckingConfiguration = .init(enableAdvancedDucking: false, duckingLevel: .min)
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, let converter = Resampler(from: format, to: Self.format) else {
            throw MicrophoneError.noInput
        }
        let tap: AVAudioNodeTapBlock = { buffer, _ in
            let samples = converter.convert(buffer)
            if !samples.isEmpty {
                onInput(samples)
            }
        }
        // Same throwing-tap form as MicrophoneEngine; macOS 27 deprecates the non-throwing one.
        try input.__installTap(
            onBus: 0, bufferSize: AVAudioFrameCount(format.sampleRate / 10), format: format, error: (), block: tap
        )
    }

    private func stopOnQueue() {
        generation += 1
        pending = 0
        queuedFrames = 0
        playbackStarted = nil
        progressTimer?.cancel()
        progressTimer = nil
        player?.stop()
        if hasInput {
            engine?.inputNode.removeTap(onBus: 0)
        }
        hasInput = false
        engine?.stop()
        engine = nil
        player = nil
    }

    private static func buffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        return buffer
    }
}
