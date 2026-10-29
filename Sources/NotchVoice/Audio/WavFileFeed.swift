//  WavFileFeed.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import FluidAudio
import Foundation

/// Plays a recording into the listening pipeline at real-time pace, followed by
/// silence, so end-of-speech detection and its latency behave as with the mic.
@MainActor
final class WavFileFeed: AudioFeed {
    private let url: URL
    private let trailingSilenceSeconds: Double
    private var task: Task<Void, Never>?

    init(url: URL, trailingSilenceSeconds: Double = 4) {
        self.url = url
        self.trailingSilenceSeconds = trailingSilenceSeconds
    }

    func start(onSamples: @escaping @Sendable ([Float]) -> Void, onFailure: @escaping @Sendable (Error) -> Void) {
        var samples: [Float]
        do {
            samples = try AudioConverter().resampleAudioFile(url)
        } catch {
            return onFailure(error)
        }
        samples += [Float](repeating: 0, count: Int(trailingSilenceSeconds * 16000))
        let chunk = 1600
        task = Task.detached(priority: .userInitiated) {
            let clock = ContinuousClock()
            let start = clock.now
            var offset = 0
            while offset < samples.count, !Task.isCancelled {
                let end = min(offset + chunk, samples.count)
                onSamples(Array(samples[offset ..< end]))
                offset = end
                try? await clock.sleep(until: start + .milliseconds(offset / 16), tolerance: .milliseconds(5))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
