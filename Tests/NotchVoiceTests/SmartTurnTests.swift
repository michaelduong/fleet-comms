//  SmartTurnTests.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation
@testable import NotchVoice
import Testing

struct SmartTurnTests {
    /// Values from transformers' WhisperFeatureExtractor(chunk_length=8) on the same signal;
    /// a mismatch here means Smart Turn sees different input than it was trained on.
    @Test func featuresMatchTheReferenceExtractor() {
        let rate = 16000.0
        let signal = (0 ..< 24000).map { index -> Float in
            let time = Double(index) / rate
            let high = time > 0.7 ? 0.1 * sin(2 * .pi * 2500 * time) : 0
            return Float(0.3 * sin(2 * .pi * 440 * time) + high)
        }
        let features = WhisperFeatures.logMel(signal)
        #expect(features.count == WhisperFeatures.melCount * WhisperFeatures.frameCount)
        // Keyed by mel bin × frameCount + frame.
        let expected: [Int: Float] = [
            0: -0.16052, 10 * 800 + 799: 1.75175, 9 * 800 + 700: 1.56066, 52 * 800 + 760: 0.33346,
            30 * 800 + 760: -0.16052, 60 * 800 + 650: 0.34763, 79 * 800 + 799: -0.01603
        ]
        for (index, reference) in expected {
            #expect(abs(features[index] - reference) < 2e-3, "index \(index): \(features[index])")
        }
        let mean = features.reduce(0, +) / Float(features.count)
        #expect(abs(mean - -0.130808) < 1e-3)
    }

    @Test func checksOncePerPause() {
        var schedule = SmartTurnSchedule()
        let checks = [0.1, 0.25, 0.5, 0, 0.3].map {
            schedule.shouldCheck(speechSeen: true, trailingSilenceSeconds: $0)
        }
        #expect(checks == [false, true, false, false, true])
    }

    @Test func waitsForSpeechBeforeChecking() {
        var schedule = SmartTurnSchedule()
        let checked = schedule.shouldCheck(speechSeen: false, trailingSilenceSeconds: 2)
        #expect(!checked)
    }
}
