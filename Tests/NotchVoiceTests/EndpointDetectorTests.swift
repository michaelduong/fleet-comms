//  EndpointDetectorTests.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

@testable import NotchVoice
import Testing

struct EndpointDetectorTests {
    private let chunk = 4096

    @Test func silenceAfterSpeechEndsTheUtterance() {
        var detector = EndpointDetector(silenceSeconds: 1.5)
        #expect(detector.update(probability: 0.9, sampleCount: chunk) == .keepListening)
        let silentChunks = Int((1.5 * 16000 / Double(chunk)).rounded(.up))
        var decisions: [EndpointDetector.Decision] = []
        for _ in 0 ..< silentChunks {
            decisions.append(detector.update(probability: 0.1, sampleCount: chunk))
        }
        #expect(decisions.dropLast().allSatisfy { $0 == .keepListening })
        #expect(decisions.last == .endOfSpeech)
    }

    @Test func speechResetsTheSilenceClock() {
        var detector = EndpointDetector(silenceSeconds: 1.0)
        _ = detector.update(probability: 0.9, sampleCount: chunk)
        for _ in 0 ..< 3 {
            _ = detector.update(probability: 0.1, sampleCount: chunk)
        }
        #expect(detector.update(probability: 0.8, sampleCount: chunk) == .keepListening)
        #expect(detector.trailingSilenceSeconds == 0)
    }

    @Test func silenceWithoutSpeechTimesOut() {
        var detector = EndpointDetector(silenceSeconds: 1.5)
        var decision = EndpointDetector.Decision.keepListening
        while decision == .keepListening {
            decision = detector.update(probability: 0.05, sampleCount: chunk)
        }
        #expect(decision == .noSpeech)
        #expect(detector.elapsedSeconds >= detector.noSpeechTimeout)
    }
}
