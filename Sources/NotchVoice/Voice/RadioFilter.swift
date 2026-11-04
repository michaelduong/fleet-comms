//  RadioFilter.swift
//  NotchVoice
//
//  Created by Michael Duong on 11/4/26.

import Foundation

/// Direct-form biquad with state retained across render blocks and sentence boundaries.
struct RadioFilter {
    private var feedZero = 1.0
    private var feedOne = 0.0
    private var feedTwo = 0.0
    private var backOne = 0.0
    private var backTwo = 0.0
    private var stateOne = 0.0
    private var stateTwo = 0.0

    enum Kind { case highPass, lowPass, peak }

    mutating func configure(_ kind: Kind, frequency: Double, rate: Double, gain: Double = 0, quality: Double = 0.707) {
        let omega = 2 * Double.pi * frequency / rate
        let cosine = cos(omega)
        let alpha = sin(omega) / (2 * quality)
        var denominator = 1 + alpha
        backOne = -2 * cosine
        backTwo = 1 - alpha
        switch kind {
        case .highPass:
            feedZero = (1 + cosine) / 2
            feedOne = -(1 + cosine)
            feedTwo = feedZero
        case .lowPass:
            feedZero = (1 - cosine) / 2
            feedOne = 1 - cosine
            feedTwo = feedZero
        case .peak:
            let amplitude = pow(10, gain / 40)
            denominator = 1 + alpha / amplitude
            feedZero = 1 + alpha * amplitude
            feedOne = -2 * cosine
            feedTwo = 1 - alpha * amplitude
            backTwo = 1 - alpha / amplitude
        }
        feedZero /= denominator
        feedOne /= denominator
        feedTwo /= denominator
        backOne /= denominator
        backTwo /= denominator
    }

    mutating func reset() {
        stateOne = 0
        stateTwo = 0
    }

    mutating func process(_ input: Double) -> Double {
        let output = input * feedZero + stateOne
        stateOne = input * feedOne - output * backOne + stateTwo
        stateTwo = input * feedTwo - output * backTwo
        return output
    }
}
