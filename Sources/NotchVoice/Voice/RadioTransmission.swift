//  RadioTransmission.swift
//  NotchVoice
//
//  Created by Michael Duong on 11/4/26.

import Foundation
import Synchronization

enum RadioStyle: String, CaseIterable, Identifiable {
    case dispatch, policeDispatch, atcTransmission

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .dispatch: "Dispatch"
        case .policeDispatch: "Police dispatch"
        case .atcTransmission: "ATC transmission"
        }
    }

    var bandwidth: (Double, Double) {
        switch self {
        case .dispatch: (350, 2700)
        case .policeDispatch: (300, 3000)
        case .atcTransmission: (300, 2500)
        }
    }

    var ratio: Double {
        switch self {
        case .dispatch: 4
        case .policeDispatch: 4.5
        case .atcTransmission: 3
        }
    }
}

/// Control values are published outside the audio callback. The kernel owns its filter state.
final class RadioControl: @unchecked Sendable {
    let enabled = Atomic<Bool>(false)
    let level = Atomic<Float>(0.25)
    let style = Atomic<Int>(1)
    let command = Atomic<Int>(0)

    func update(defaults: UserDefaults = .standard, bypass: Bool = false) {
        enabled.store(!bypass && defaults.bool(forKey: "radioEnabled"), ordering: .relaxed)
        let raw = defaults.object(forKey: "radioStaticLevel") == nil ? 25 : defaults.double(forKey: "radioStaticLevel")
        level.store(Float(min(100, max(0, raw))) / 100, ordering: .relaxed)
        let selected = defaults.string(forKey: "radioStyle").flatMap(RadioStyle.init) ?? .policeDispatch
        style.store(RadioStyle.allCases.firstIndex(of: selected) ?? 1, ordering: .relaxed)
    }
}

/// Original, stateful output-only DSP. No allocation, preference reads or random system calls occur per sample.
final class RadioKernel: @unchecked Sendable {
    let control: RadioControl
    private let noise: [Float]
    private var noiseIndex = 0
    private var highPass1 = RadioFilter()
    private var highPass2 = RadioFilter()
    private var lowPass1 = RadioFilter()
    private var lowPass2 = RadioFilter()
    private var receiver = RadioFilter()
    private var speaker = RadioFilter()
    private var configuredStyle: RadioStyle?
    private var configuredRate = 0.0
    private var attackCoefficient = 0.0
    private var releaseCoefficient = 0.0
    private var noiseCoefficient = 0.0
    private var started = false
    private var openingFrames = 0
    private var tailFrames = 0
    private var elapsedFrames = 0
    private var interruptedFrames = 0
    private var lastOutput: Float = 0
    private var cancelled = false
    private var noiseLowPass = 0.0
    private var noisePrevious = 0.0
    private var envelope = 0.0
    private var wet = 0.0
    private var staticLevel = 0.25

    init(control: RadioControl) {
        self.control = control
        var seed: UInt32 = 0xA17C_901D
        noise = (0 ..< 65536).map { _ in
            seed ^= seed << 13
            seed ^= seed >> 17
            seed ^= seed << 5
            return Float(Double(seed) / Double(UInt32.max) * 2 - 1)
        }
    }

    func prepare(sampleRate: Double, style: RadioStyle) {
        switch control.command.exchange(0, ordering: .relaxed) {
        case 1:
            resetVoice()
        case 2:
            if started {
                tailFrames = Int(sampleRate * (style == .policeDispatch ? 0.11 : 0.055))
            }
        case 3:
            cancelled = true
            interruptedFrames = Int(sampleRate * 0.01)
            started = false
            tailFrames = 0
            openingFrames = 0
        default: break
        }
        guard configuredStyle != style || configuredRate != sampleRate else { return }
        configuredStyle = style
        configuredRate = sampleRate
        let (low, high) = style.bandwidth
        highPass1.configure(.highPass, frequency: low, rate: sampleRate)
        highPass2.configure(.highPass, frequency: low, rate: sampleRate)
        lowPass1.configure(.lowPass, frequency: high, rate: sampleRate)
        lowPass2.configure(.lowPass, frequency: high, rate: sampleRate)
        receiver.configure(.lowPass, frequency: high, rate: sampleRate)
        speaker.configure(
            .peak,
            frequency: style == .policeDispatch ? 1700 : (style == .dispatch ? 1550 : 1450),
            rate: sampleRate,
            gain: style == .dispatch ? 3 : (style == .policeDispatch ? 2 : 1.5),
            quality: style == .atcTransmission ? 0.85 : 0.75
        )
        let attack = style == .policeDispatch ? 0.004 : (style == .dispatch ? 0.003 : 0.006)
        let release = style == .policeDispatch ? 0.08 : (style == .dispatch ? 0.1 : 0.12)
        attackCoefficient = exp(-1 / (attack * sampleRate))
        releaseCoefficient = exp(-1 / (release * sampleRate))
        noiseCoefficient = 1 - exp(-2 * Double.pi * (style == .policeDispatch ? 4800 : 3300) / sampleRate)
    }

    private func resetVoice() {
        started = false
        tailFrames = 0
        openingFrames = 0
        elapsedFrames = 0
        interruptedFrames = 0
        cancelled = false
        highPass1.reset()
        highPass2.reset()
        lowPass1.reset()
        lowPass2.reset()
        receiver.reset()
        speaker.reset()
        envelope = 0
    }

    private func noiseBed(style: RadioStyle, sampleRate: Double, hasAudio: Bool) -> Double {
        let speech = min(1, envelope / 0.065)
        var bed: Double
        switch style {
        case .dispatch: bed = 0.0158
        case .policeDispatch: bed = 0.0045 + 0.0065 * (1 - speech)
        case .atcTransmission:
            let time = Double(elapsedFrames) / sampleRate
            bed = (0.006 + 0.0035 * (1 - speech)) * (1 + 0.12 * sin(2 * .pi * 2.1 * time))
        }
        // Normalized shaped noise; 25% is the profile's reference amplitude, not device volume.
        bed = hasAudio && started ? bed : 0
        if openingFrames > 0, hasAudio {
            bed += style == .policeDispatch ? 0.014 : 0.012
            openingFrames -= 1
        }
        if tailFrames > 0 {
            let duration = sampleRate * (style == .policeDispatch ? 0.11 : 0.055)
            let fade = min(1, Double(tailFrames) / (sampleRate * 0.006))
            bed = (style == .policeDispatch ? 0.025 : 0.017) * fade * min(
                1,
                (duration - Double(tailFrames)) / (sampleRate * 0.004)
            )
            tailFrames -= 1
        }
        elapsedFrames += 1
        return bed
    }

    func process(
        _ input: Float,
        sampleRate: Double,
        enabled: Bool,
        level: Float,
        style: RadioStyle,
        hasAudio: Bool = true
    ) -> Float {
        guard sampleRate.isFinite, sampleRate > 6000, input.isFinite else { return input.isFinite ? input : 0 }
        if interruptedFrames > 0 {
            let value = lastOutput * Float(Double(interruptedFrames) / (sampleRate * 0.01))
            interruptedFrames -= 1
            return value
        }
        if cancelled {
            return 0
        }
        let dry = Double(input)
        if !started, abs(dry) > 0.0001 {
            started = true
            openingFrames = Int(sampleRate * (style == .policeDispatch ? 0.014 : 0.03))
        }
        let filtered = lowPass2.process(lowPass1.process(highPass2.process(highPass1.process(dry))))
        let coefficient = abs(filtered) > envelope ? attackCoefficient : releaseCoefficient
        envelope = coefficient * envelope + (1 - coefficient) * abs(filtered)
        let threshold = style == .dispatch ? 0.0501187234 : 0.0562341325 // -26 / -25 dBFS, from the comparisons.
        let gain = envelope > threshold ? pow(envelope / threshold, 1 / style.ratio - 1) : 1
        let drive = style == .dispatch ? 1.9 : (style == .policeDispatch ? 1.45 : 1.25)
        let voice = tanh(filtered * gain * 2 * drive) / tanh(drive)
        let received = receiver.process(speaker.process(voice))
        let random = Double(noise[noiseIndex])
        noiseIndex = (noiseIndex + 1) % noise.count
        let shaped = random - noisePrevious
        noisePrevious = random
        noiseLowPass += noiseCoefficient * (shaped - noiseLowPass)
        let step = 1 / (sampleRate * 0.01)
        wet += min(step, max(-step, (enabled ? 1 : 0) - wet))
        staticLevel += min(step, max(-step, Double(level) - staticLevel))
        let bed = noiseBed(style: style, sampleRate: sampleRate, hasAudio: hasAudio)
        let radio = received + noiseLowPass * 2.4 * bed * staticLevel * 4
        let output = dry * (1 - wet) + max(-0.95, min(0.95, radio)) * wet
        lastOutput = output.isFinite ? Float(output) : input
        return lastOutput
    }
}
