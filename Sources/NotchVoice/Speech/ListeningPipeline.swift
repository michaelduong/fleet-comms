//  ListeningPipeline.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import FluidAudio
import Foundation

/// Feeds one utterance through Silero VAD and the speech model, and reports when it
/// is over: the model's end-of-utterance, Smart Turn judging a pause complete, or
/// `silenceSeconds` of quiet after speech.
actor ListeningPipeline {
    struct Update: Sendable {
        let partial: String
        let decision: EndpointDetector.Decision
        let trailingSilenceSeconds: Double
        let elapsedSeconds: Double
        let endedBy: String?
        let speechAccepted: Bool
    }

    private let recognizer: any SpeechRecognizer
    private let vad: VadManager
    private let smartTurn: SmartTurn?
    private var vadState: VadStreamState
    private var vadBuffer: [Float] = []
    private var detector: EndpointDetector
    private var schedule = SmartTurnSchedule()
    private var recentAudio: [Float] = []
    private var partial = ""
    private let minimumSpeechSeconds: Double
    private var speechSamples = 0

    init(
        recognizer: any SpeechRecognizer, vad: VadManager, smartTurn: SmartTurn?,
        silenceSeconds: Double, minimumSpeechSeconds: Double = 0
    ) async {
        self.minimumSpeechSeconds = minimumSpeechSeconds
        self.recognizer = recognizer
        self.vad = vad
        self.smartTurn = smartTurn
        vadState = await vad.makeStreamState()
        detector = EndpointDetector(silenceSeconds: silenceSeconds)
        await recognizer.reset()
    }

    func process(_ samples: [Float]) async throws -> Update {
        partial = try await recognizer.append(samples)
        if smartTurn != nil {
            keepRecent(samples)
        }
        var decision = try await processVad(samples)
        let accepted = detector.speechSeen && Double(speechSamples) / 16000 >= minimumSpeechSeconds
        var endedBy = decision == .endOfSpeech ? "silence" : nil
        if decision == .keepListening, detector.speechSeen, await recognizer.endOfUtteranceDetected() {
            decision = .endOfSpeech
            endedBy = "model_eou"
        }
        if accepted, decision == .keepListening, try await smartTurnSaysComplete() {
            decision = .endOfSpeech
            endedBy = "smart_turn"
        }
        if !accepted, decision == .endOfSpeech {
            await rejectShortBurst()
            decision = .keepListening
            endedBy = nil
        }
        return Update(
            partial: partial, decision: decision,
            trailingSilenceSeconds: detector.trailingSilenceSeconds,
            elapsedSeconds: detector.elapsedSeconds, endedBy: endedBy, speechAccepted: accepted
        )
    }

    func finish() async throws -> String {
        let text = try await recognizer.finish()
        let final = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return final.isEmpty ? partial.trimmingCharacters(in: .whitespacesAndNewlines) : final
    }

    private func processVad(_ samples: [Float]) async throws -> EndpointDetector.Decision {
        vadBuffer += samples
        var decision = EndpointDetector.Decision.keepListening
        while vadBuffer.count >= VadManager.chunkSize, decision == .keepListening {
            let chunk = Array(vadBuffer.prefix(VadManager.chunkSize))
            vadBuffer.removeFirst(VadManager.chunkSize)
            let result = try await vad.processStreamingChunk(chunk, state: vadState)
            vadState = result.state
            if result.probability >= EndpointDetector.speechThreshold {
                speechSamples += chunk.count
            }
            decision = detector.update(probability: result.probability, sampleCount: chunk.count)
        }
        return decision
    }

    private func rejectShortBurst() async {
        detector = EndpointDetector(silenceSeconds: detector.silenceSeconds)
        speechSamples = 0
        schedule = SmartTurnSchedule()
        recentAudio = []
        await recognizer.reset()
        partial = ""
    }

    private func smartTurnSaysComplete() async throws -> Bool {
        guard let smartTurn, schedule.shouldCheck(
            speechSeen: detector.speechSeen, trailingSilenceSeconds: detector.trailingSilenceSeconds
        ) else { return false }
        let started = Date()
        let probability = try await smartTurn.completionProbability(recentAudio)
        EventLog.record("smart_turn_checked", [
            "probability": String(format: "%.3f", probability),
            "pause_ms": String(Int(detector.trailingSilenceSeconds * 1000)),
            "audio_ms": String(Int(detector.elapsedSeconds * 1000)),
            "inference_ms": EventLog.milliseconds(from: started)
        ])
        return probability >= SmartTurn.completeThreshold
    }

    private func keepRecent(_ samples: [Float]) {
        recentAudio += samples
        if recentAudio.count > WhisperFeatures.sampleCount {
            recentAudio.removeFirst(recentAudio.count - WhisperFeatures.sampleCount)
        }
    }
}
