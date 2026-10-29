//  AudioFeed.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation

/// A source of 16 kHz mono Float32 samples: the microphone, or a WAV file played
/// through the same pipeline for testing.
@MainActor
protocol AudioFeed: AnyObject {
    func start(onSamples: @escaping @Sendable ([Float]) -> Void, onFailure: @escaping @Sendable (Error) -> Void)
    func stop()
}

enum AudioLevel {
    /// RMS mapped from -55 dBFS...-10 dBFS onto 0...1 for the level meter.
    static func normalized(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let meanSquare = samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(samples.count)
        let decibels = 10 * log10(max(meanSquare, 1e-10))
        return min(max((decibels + 55) / 45, 0), 1)
    }
}
