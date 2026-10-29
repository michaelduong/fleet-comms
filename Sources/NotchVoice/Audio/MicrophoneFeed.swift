//  MicrophoneFeed.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

@preconcurrency import AVFoundation

/// The microphone, running only between `start` and `stop` so the mic is off otherwise.
@MainActor
final class MicrophoneFeed: AudioFeed {
    private let engine = MicrophoneEngine()

    func start(onSamples: @escaping @Sendable ([Float]) -> Void, onFailure: @escaping @Sendable (Error) -> Void) {
        engine.start(onSamples: onSamples, onFailure: onFailure)
    }

    func stop() {
        engine.stop()
    }
}

/// Owns the AVAudioEngine on its own queue: starting input on a Bluetooth headset
/// can block for seconds while the route switches, which must not freeze the pill.
final class MicrophoneEngine: @unchecked Sendable {
    private let queue = DispatchQueue(label: "io.github.michaelduong.fleetcomms.microphone")
    private var engine: AVAudioEngine?

    func start(onSamples: @escaping @Sendable ([Float]) -> Void, onFailure: @escaping @Sendable (Error) -> Void) {
        queue.async { [self] in
            do {
                try startOnQueue(onSamples: onSamples)
            } catch {
                stopOnQueue()
                onFailure(error)
            }
        }
    }

    func stop() {
        queue.async { [self] in stopOnQueue() }
    }

    private func startOnQueue(onSamples: @escaping @Sendable ([Float]) -> Void) throws {
        let engine = AVAudioEngine()
        self.engine = engine
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, let converter = Resampler(from: format) else {
            throw MicrophoneError.noInput
        }
        try Self.installTap(on: input, format: format, converter: converter, onSamples: onSamples)
        engine.prepare()
        try engine.start()
    }

    private static func installTap(
        on input: AVAudioInputNode,
        format: AVAudioFormat,
        converter: Resampler,
        onSamples: @escaping @Sendable ([Float]) -> Void
    ) throws {
        let bufferSize = AVAudioFrameCount(format.sampleRate / 10)
        // macOS 27 deprecates the non-throwing tap; the SDK imports its throwing replacement only in this form.
        let tap: AVAudioNodeTapBlock = { buffer, _ in
            let samples = converter.convert(buffer)
            if !samples.isEmpty {
                onSamples(samples)
            }
        }
        try input.__installTap(onBus: 0, bufferSize: bufferSize, format: format, error: (), block: tap)
    }

    private func stopOnQueue() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
    }
}

enum MicrophoneError: LocalizedError {
    case noInput
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .noInput: "No microphone input is available."
        case .permissionDenied: "Microphone access is off. Allow Fleet Comms in System Settings › Privacy › Microphone."
        }
    }
}

/// Converts capture buffers to mono Float32, 16 kHz unless asked for another rate.
final class Resampler: @unchecked Sendable {
    static let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false
    )!

    private let converter: AVAudioConverter
    private let target: AVAudioFormat

    init?(from format: AVAudioFormat, to target: AVAudioFormat = targetFormat) {
        guard let converter = AVAudioConverter(from: format, to: target) else { return nil }
        // Voice processing delivers nine identical channels, and the default downmix of those
        // to mono comes out silent; take the first channel instead.
        if format.channelCount > target.channelCount {
            converter.channelMap = [0]
        }
        self.converter = converter
        self.target = target
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> [Float] {
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return [] }
        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let channel = output.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }
}
