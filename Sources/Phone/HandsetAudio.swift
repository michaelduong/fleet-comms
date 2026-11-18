//  HandsetAudio.swift
//  FleetCommsPhone
//
//  Created by Michael Duong on 11/17/26.

@preconcurrency import AVFoundation

/// One engine for both directions: the microphone converted to 16 kHz mono for the Mac, and the Mac's
/// 24 kHz reply speech queued on a player node.
final class HandsetAudio: @unchecked Sendable {
    var onMicSamples: (@Sendable ([Float]) -> Void)?
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let speechFormat = AVAudioFormat(standardFormatWithSampleRate: PhoneLink.speechRate, channels: 1)!
    private let micFormat = AVAudioFormat(standardFormatWithSampleRate: PhoneLink.micRate, channels: 1)!
    private let lock = NSLock()
    private var pending = 0
    private var micRunning = false
    private var configured = false

    var pendingBuffers: Int {
        lock.withLock { pending }
    }

    /// Frames played since the first queued buffer, in the speech format's rate.
    var playedFrames: Int64 {
        guard let render = player.lastRenderTime, let time = player.playerTime(forNodeTime: render) else { return 0 }
        return max(0, time.sampleTime)
    }

    private func configure() -> Bool {
        if configured {
            return true
        }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
        } catch { return false }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: speechFormat)
        configured = true
        return true
    }

    func startMic() -> Bool {
        guard configure(), !micRunning else { return micRunning }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, let converter = AVAudioConverter(from: format, to: micFormat) else { return false }
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            self?.forward(buffer, through: converter)
        }
        do {
            if !engine.isRunning {
                try engine.start()
            }
        } catch {
            input.removeTap(onBus: 0)
            return false
        }
        micRunning = true
        return true
    }

    func stopMic() {
        guard micRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        micRunning = false
    }

    private func forward(_ buffer: AVAudioPCMBuffer, through converter: AVAudioConverter) {
        let ratio = micFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: micFormat, frameCapacity: capacity) else { return }
        nonisolated(unsafe) var supplied = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let channel = out.floatChannelData?[0], out.frameLength > 0 else { return }
        onMicSamples?(Array(UnsafeBufferPointer(start: channel, count: Int(out.frameLength))))
    }

    func play(_ samples: [Float], onDrained: @escaping @Sendable () -> Void) {
        guard configure(), !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: speechFormat, frameCapacity: AVAudioFrameCount(samples.count))
        else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples
            .withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        do {
            if !engine.isRunning {
                try engine.start()
            }
        } catch { return }
        lock.withLock { pending += 1 }
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            self?.lock.withLock { self?.pending -= 1 }
            onDrained()
        }
        if !player.isPlaying {
            player.play()
        }
    }

    func stopPlayback() {
        player.stop()
        lock.withLock { pending = 0 }
    }
}
