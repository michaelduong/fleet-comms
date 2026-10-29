//  RealtimePCM.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation

/// The realtime wire carries 24 kHz mono 16-bit little-endian PCM.
enum RealtimePCM {
    static func encode(_ samples: [Float]) -> Data {
        var data = Data(capacity: samples.count * 2)
        for sample in samples {
            let value = Int16(max(-1, min(1, sample)) * Float(Int16.max)).littleEndian
            withUnsafeBytes(of: value) { data.append(contentsOf: $0) }
        }
        return data
    }

    static func decode(_ data: Data) -> [Float] {
        let count = data.count / 2
        var samples = [Float](repeating: 0, count: count)
        data.withUnsafeBytes { raw in
            for index in 0 ..< count {
                let value = Int16(littleEndian: raw.loadUnaligned(fromByteOffset: index * 2, as: Int16.self))
                samples[index] = Float(value) / Float(Int16.max)
            }
        }
        return samples
    }

    /// The WAV test feed delivers 16 kHz; linear interpolation to 24 kHz is plenty for speech.
    static func upsample16kTo24k(_ samples: [Float]) -> [Float] {
        guard samples.count > 1 else { return samples }
        let outputCount = samples.count * 3 / 2
        return (0 ..< outputCount).map { index in
            let position = Double(index) * 2 / 3
            let lower = Int(position)
            let upper = min(lower + 1, samples.count - 1)
            let fraction = Float(position - Double(lower))
            return samples[lower] + (samples[upper] - samples[lower]) * fraction
        }
    }
}
