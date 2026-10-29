//  SmartTurn.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation
@preconcurrency import OnnxRuntimeBindings

/// Smart Turn v3 (pipecat-ai, BSD-2-Clause): from the last 8 s of a turn's audio, the
/// probability that the speaker has finished. Runs on the CPU through ONNX Runtime.
actor SmartTurn {
    static let completeThreshold: Float = 0.5

    private let environment: ORTEnv
    private let session: ORTSession

    init(modelURL: URL) throws {
        environment = try ORTEnv(loggingLevel: .warning)
        let options = try ORTSessionOptions()
        try options.setGraphOptimizationLevel(.all)
        session = try ORTSession(env: environment, modelPath: modelURL.path, sessionOptions: options)
    }

    func completionProbability(_ audio: [Float]) throws -> Float {
        let features = WhisperFeatures.logMel(audio)
        let data = features.withUnsafeBytes { NSMutableData(bytes: $0.baseAddress, length: $0.count) }
        let shape = [1, WhisperFeatures.melCount, WhisperFeatures.frameCount].map { NSNumber(value: $0) }
        let input = try ORTValue(tensorData: data, elementType: .float, shape: shape)
        let outputs = try session.run(withInputs: ["input_features": input], outputNames: ["logits"], runOptions: nil)
        guard let output = try outputs["logits"]?.tensorData() as Data?, output.count >= MemoryLayout<Float>.size else {
            throw SmartTurnError.noOutput
        }
        return output.withUnsafeBytes { $0.load(as: Float.self) }
    }
}

/// Smart Turn is asked once per pause, as soon as the pause is `pauseSeconds` long;
/// speech re-arms it for the next pause.
struct SmartTurnSchedule {
    static let pauseSeconds = 0.2

    private var checkedThisPause = false

    mutating func shouldCheck(speechSeen: Bool, trailingSilenceSeconds: Double) -> Bool {
        guard speechSeen, trailingSilenceSeconds >= Self.pauseSeconds else {
            checkedThisPause = false
            return false
        }
        guard !checkedThisPause else { return false }
        checkedThisPause = true
        return true
    }
}

enum SmartTurnError: LocalizedError {
    case noOutput
    case checksumMismatch

    var errorDescription: String? {
        switch self {
        case .noOutput: "Smart Turn returned no result."
        case .checksumMismatch: "The Smart Turn download was damaged."
        }
    }
}
