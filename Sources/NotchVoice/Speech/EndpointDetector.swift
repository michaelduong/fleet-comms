//  EndpointDetector.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation

/// Decides when an utterance is over from per-chunk voice probabilities:
/// speech followed by `silenceSeconds` of quiet ends it.
struct EndpointDetector {
    enum Decision: Equatable {
        case keepListening
        case endOfSpeech
        case noSpeech
        case maxLength
    }

    static let sampleRate = 16000.0
    static let speechThreshold: Float = 0.5

    let silenceSeconds: Double
    var noSpeechTimeout: Double = 8
    var maxUtteranceSeconds: Double = 90

    private(set) var speechSeen = false
    private(set) var processedSamples = 0
    private var lastSpeechSample = 0

    init(silenceSeconds: Double) {
        self.silenceSeconds = silenceSeconds
    }

    var elapsedSeconds: Double {
        Double(processedSamples) / Self.sampleRate
    }

    var trailingSilenceSeconds: Double {
        Double(processedSamples - lastSpeechSample) / Self.sampleRate
    }

    mutating func update(probability: Float, sampleCount: Int) -> Decision {
        processedSamples += sampleCount
        if probability >= Self.speechThreshold {
            speechSeen = true
            lastSpeechSample = processedSamples
        }
        if speechSeen, trailingSilenceSeconds >= silenceSeconds {
            return .endOfSpeech
        }
        if !speechSeen, elapsedSeconds >= noSpeechTimeout {
            return .noSpeech
        }
        if elapsedSeconds >= maxUtteranceSeconds {
            return .maxLength
        }
        return .keepListening
    }
}
