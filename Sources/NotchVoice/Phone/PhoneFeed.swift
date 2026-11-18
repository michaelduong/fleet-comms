//  PhoneFeed.swift
//  NotchVoice
//
//  Created by Michael Duong on 11/17/26.

import Foundation

/// The phone's microphone, arriving over the link as 16 kHz samples, feeding the same listening pipeline
/// as the Mac's own microphone.
@MainActor
final class PhoneFeed: AudioFeed {
    private var onSamples: (@Sendable ([Float]) -> Void)?

    func start(onSamples: @escaping @Sendable ([Float]) -> Void, onFailure: @escaping @Sendable (Error) -> Void) {
        self.onSamples = onSamples
    }

    func stop() {
        onSamples = nil
    }

    func receive(_ samples: [Float]) {
        onSamples?(samples)
    }

    /// Releasing the button means "that was all": silence past any pause threshold ends the turn at once,
    /// through the same detector a pause would reach.
    func release() {
        let chunk = [Float](repeating: 0, count: 1600)
        for _ in 0 ..< 40 {
            onSamples?(chunk)
        }
    }
}
