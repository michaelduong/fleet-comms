//  PhoneRadioRenderer.swift
//  NotchVoice
//
//  Created by Michael Duong on 11/17/26.

import Foundation

/// Runs reply speech through the desktop's radio kernel without an audio engine, so the phone gets the same
/// squelch burst, band limit, static and closing tail the Mac's speakers would.
final class PhoneRadioRenderer {
    private let control = RadioControl()
    private let kernel: RadioKernel
    private let rate = PhoneLink.speechRate

    init() {
        kernel = RadioKernel(control: control)
    }

    func begin(defaults: UserDefaults = .standard) {
        control.update(defaults: defaults)
        control.command.store(1, ordering: .relaxed)
        _ = render([], hasAudio: false)
    }

    func render(_ samples: [Float], hasAudio: Bool = true) -> [Float] {
        let radio = control.snapshot
        kernel.prepare(sampleRate: rate, style: radio.style)
        return samples.map {
            kernel.process(
                $0, sampleRate: rate, enabled: radio.enabled, level: radio.level, style: radio.style,
                hasAudio: hasAudio
            )
        }
    }

    /// The closing tail: silence in, the kernel's last burst out. Empty when the radio effect is off.
    func finish() -> [Float] {
        guard control.enabled.load(ordering: .relaxed) else { return [] }
        control.command.store(2, ordering: .relaxed)
        let seconds = control.style.load(ordering: .relaxed) == 1 ? 0.12 : 0.065
        return render([Float](repeating: 0, count: Int(rate * seconds)), hasAudio: false)
    }
}
