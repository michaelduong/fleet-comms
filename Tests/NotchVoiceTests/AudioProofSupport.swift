//  AudioProofSupport.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import AVFoundation
import Foundation
@testable import NotchVoice
import Testing

enum AudioProofSupport {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["NOTCH_VOICE_AUDIO_PROOF_ROOT"] != nil
    }

    static var root: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["NOTCH_VOICE_AUDIO_PROOF_ROOT"]!)
    }

    @MainActor
    static func eventually(seconds: Double = 15, _ check: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !check(), Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(check())
    }

    static func writeWav(_ samples: [Float], name: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        samples
            .withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    static func record(_ line: String) throws {
        let url = root.appendingPathComponent("audio-proof.txt")
        if !FileManager.default.fileExists(atPath: url.path) {
            try Data().write(to: url)
        }
        let handle = try FileHandle(forWritingTo: url)
        handle.seekToEndOfFile()
        handle.write(Data((line + "\n").utf8))
        try handle.close()
    }
}
