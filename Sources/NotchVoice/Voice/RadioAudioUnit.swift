//  RadioAudioUnit.swift
//  NotchVoice
//
//  Created by Michael Duong on 11/4/26.

import AudioToolbox
@preconcurrency import AVFoundation

/// An output insert rather than a buffer transform: controls also affect audio already queued by either player.
final class RadioAudioUnit: AUAudioUnit, @unchecked Sendable {
    let control = RadioControl()
    private var inputBus: AUAudioUnitBus!
    private var outputBus: AUAudioUnitBus!
    private var inputs: AUAudioUnitBusArray!
    private var outputs: AUAudioUnitBusArray!
    private var kernel: RadioKernel!

    override init(
        componentDescription: AudioComponentDescription,
        options: AudioComponentInstantiationOptions = []
    ) throws {
        try super.init(componentDescription: componentDescription, options: options)
        let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
        inputBus = try AUAudioUnitBus(format: format)
        outputBus = try AUAudioUnitBus(format: format)
        inputs = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [inputBus])
        outputs = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
        kernel = RadioKernel(control: control)
        maximumFramesToRender = 4096
    }

    override var inputBusses: AUAudioUnitBusArray {
        inputs
    }

    override var outputBusses: AUAudioUnitBusArray {
        outputs
    }

    override var internalRenderBlock: AUInternalRenderBlock {
        let kernel = kernel!
        let control = control
        let rate = outputBus.format.sampleRate
        return { flags, timestamp, count, _, output, _, pull in
            guard let pull else { return kAudioUnitErr_NoConnection }
            let status = pull(flags, timestamp, count, 0, output)
            guard status == noErr else { return status }
            let enabled = control.enabled.load(ordering: .relaxed)
            let level = control.level.load(ordering: .relaxed)
            let index = control.style.load(ordering: .relaxed)
            let style: RadioStyle = index == 0 ? .dispatch : (index == 2 ? .atcTransmission : .policeDispatch)
            kernel.prepare(sampleRate: rate, style: style)
            let hasAudio = !flags.pointee.contains(.unitRenderAction_OutputIsSilence)
            let buffers = UnsafeMutableAudioBufferListPointer(output)
            guard let data = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            for frame in 0 ..< Int(count) {
                data[frame] = kernel.process(
                    data[frame],
                    sampleRate: rate,
                    enabled: enabled,
                    level: level,
                    style: style,
                    hasAudio: hasAudio
                )
            }
            flags.pointee.remove(.unitRenderAction_OutputIsSilence)
            return noErr
        }
    }
}

final class RadioOutput {
    private static let description = AudioComponentDescription(
        componentType: kAudioUnitType_Effect, componentSubType: 0x466C_5278,
        componentManufacturer: 0x466C_436D, componentFlags: 0, componentFlagsMask: 0
    )
    private static let registered: Void = AUAudioUnit.registerSubclass(
        RadioAudioUnit.self, as: description, name: "Fleet Comms: Radio", version: 1
    )

    private var timer: DispatchSourceTimer?
    private let unit: AVAudioUnit

    func begin() {
        (unit.auAudioUnit as? RadioAudioUnit)?.control.command.store(1, ordering: .relaxed)
    }

    func finish() -> Double {
        guard let radio = unit.auAudioUnit as? RadioAudioUnit,
              radio.control.enabled.load(ordering: .relaxed) else { return 0 }
        radio.control.command.store(2, ordering: .relaxed)
        return radio.control.style.load(ordering: .relaxed) == 1 ? 0.12 : 0.065
    }

    @discardableResult
    func cancel() -> Double {
        guard let radio = unit.auAudioUnit as? RadioAudioUnit else { return 0 }
        radio.control.command.store(3, ordering: .relaxed)
        return radio.control.enabled.load(ordering: .relaxed) ? 0.015 : 0
    }

    init(
        engine: AVAudioEngine,
        player: AVAudioPlayerNode,
        format: AVAudioFormat,
        bypass: Bool = false,
        defaults: UserDefaults = .standard
    ) throws {
        _ = Self.registered
        let unit = AVAudioUnitEffect(audioComponentDescription: Self.description)
        self.unit = unit
        engine.attach(unit)
        do {
            try engine.connectNode(player, to: unit, format: format)
            try engine.connectNode(unit, to: engine.mainMixerNode, format: format)
        } catch {
            engine.disconnectNodeOutput(player)
            engine.detach(unit)
            throw error
        }
        if let radio = unit.auAudioUnit as? RadioAudioUnit {
            radio.control.update(defaults: defaults, bypass: bypass)
            let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
            timer.schedule(deadline: .now(), repeating: .milliseconds(10))
            timer.setEventHandler { radio.control.update(defaults: defaults, bypass: bypass) }
            timer.resume()
            self.timer = timer
        }
    }

    deinit { timer?.cancel() }
}
