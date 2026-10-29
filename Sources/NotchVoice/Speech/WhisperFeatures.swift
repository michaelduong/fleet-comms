//  WhisperFeatures.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Accelerate
import Foundation

/// Whisper's 80-bin log-mel spectrogram of the last 8 s of 16 kHz audio, as Smart Turn was
/// trained on: transformers' `WhisperFeatureExtractor(chunk_length: 8)` with `do_normalize`.
/// Output is mel-major, `melCount × frameCount`.
enum WhisperFeatures {
    static let sampleCount = 8 * 16000
    static let melCount = 80
    static let frameCount = 800

    private static let fftLength = 400
    private static let hop = 160
    private static let binCount = fftLength / 2 + 1

    static func logMel(_ audio: [Float]) -> [Float] {
        let window = normalized(lastEightSeconds(audio))
        let power = powerSpectrum(framed(reflectPadded(window)))
        var mel = [Float](repeating: 0, count: frameCount * melCount)
        vDSP_mmul(
            power,
            1,
            melFilters,
            1,
            &mel,
            1,
            vDSP_Length(frameCount),
            vDSP_Length(melCount),
            vDSP_Length(binCount)
        )
        var floor: Float = 1e-10
        vDSP_vthr(mel, 1, &floor, &mel, 1, vDSP_Length(mel.count))
        var count = Int32(mel.count)
        vvlog10f(&mel, mel, &count)
        var features = [Float](repeating: 0, count: mel.count)
        vDSP_mtrans(mel, 1, &features, 1, vDSP_Length(melCount), vDSP_Length(frameCount))
        var top: Float = 0
        vDSP_maxv(features, 1, &top, vDSP_Length(features.count))
        var lowest = top - 8
        vDSP_vthr(features, 1, &lowest, &features, 1, vDSP_Length(features.count))
        var scale: Float = 0.25
        var offset: Float = 1
        vDSP_vsmsa(features, 1, &scale, &offset, &features, 1, vDSP_Length(features.count))
        return features
    }

    /// Keeps the end of longer audio; pads shorter audio with leading silence.
    private static func lastEightSeconds(_ audio: [Float]) -> [Float] {
        audio.count >= sampleCount
            ? Array(audio.suffix(sampleCount))
            : [Float](repeating: 0, count: sampleCount - audio.count) + audio
    }

    private static func normalized(_ audio: [Float]) -> [Float] {
        let mean = vDSP.mean(audio)
        let centered = vDSP.add(-mean, audio)
        let variance = vDSP.meanSquare(centered)
        return vDSP.multiply(1 / (variance + 1e-7).squareRoot(), centered)
    }

    private static func reflectPadded(_ audio: [Float]) -> [Float] {
        let pad = fftLength / 2
        let head = (1 ... pad).reversed().map { audio[$0] }
        let tail = (1 ... pad).map { audio[audio.count - 1 - $0] }
        return head + audio + tail
    }

    /// `frameCount × fftLength`, each frame windowed. Whisper drops the final centred frame.
    private static func framed(_ padded: [Float]) -> [Float] {
        var frames = [Float](repeating: 0, count: frameCount * fftLength)
        padded.withUnsafeBufferPointer { source in
            frames.withUnsafeMutableBufferPointer { target in
                for frame in 0 ..< frameCount {
                    vDSP_vmul(
                        source.baseAddress! + frame * hop,
                        1,
                        hannWindow,
                        1,
                        target.baseAddress! + frame * fftLength,
                        1,
                        vDSP_Length(fftLength)
                    )
                }
            }
        }
        return frames
    }

    /// 400 is not a length vDSP's FFT supports, so the DFT is two matrix products.
    private static func powerSpectrum(_ frames: [Float]) -> [Float] {
        let count = frameCount * binCount
        var real = [Float](repeating: 0, count: count)
        var imaginary = [Float](repeating: 0, count: count)
        let rows = vDSP_Length(frameCount), columns = vDSP_Length(binCount), inner = vDSP_Length(fftLength)
        vDSP_mmul(frames, 1, dftCosines, 1, &real, 1, rows, columns, inner)
        vDSP_mmul(frames, 1, dftSines, 1, &imaginary, 1, rows, columns, inner)
        return vDSP.add(vDSP.square(real), vDSP.square(imaginary))
    }

    private static let hannWindow: [Float] = (0 ..< fftLength).map {
        Float(0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(fftLength)))
    }

    private static let dftCosines = dftMatrix(cos)
    private static let dftSines = dftMatrix(sin)

    /// `fftLength × binCount`.
    private static func dftMatrix(_ wave: (Double) -> Double) -> [Float] {
        (0 ..< fftLength).flatMap { sample in
            (0 ..< binCount).map { bin in
                Float(wave(2 * Double.pi * Double(sample * bin % fftLength) / Double(fftLength)))
            }
        }
    }

    /// Slaney-scale, Slaney-normalised triangular filters from 0 to 8 kHz, `binCount × melCount`.
    private static let melFilters: [Float] = {
        let low = slaneyMel(0), high = slaneyMel(8000)
        let edges = (0 ... melCount + 1).map { slaneyHertz(low + (high - low) * Double($0) / Double(melCount + 1)) }
        return (0 ..< binCount).flatMap { bin in
            let hertz = 8000 * Double(bin) / Double(binCount - 1)
            return (0 ..< melCount).map { mel in
                let rising = (hertz - edges[mel]) / (edges[mel + 1] - edges[mel])
                let falling = (edges[mel + 2] - hertz) / (edges[mel + 2] - edges[mel + 1])
                let area = 2 / (edges[mel + 2] - edges[mel])
                return Float(max(0, min(rising, falling)) * area)
            }
        }
    }()

    private static let logStep = 27 / log(6.4)

    private static func slaneyMel(_ hertz: Double) -> Double {
        hertz < 1000 ? 3 * hertz / 200 : 15 + log(hertz / 1000) * logStep
    }

    private static func slaneyHertz(_ mel: Double) -> Double {
        mel < 15 ? 200 * mel / 3 : 1000 * exp((mel - 15) / logStep)
    }
}
