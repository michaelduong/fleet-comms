//  AppModel+Listening.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import AVFoundation
import Foundation

/// When the utterance was judged over, and when the speaker last made a sound.
struct Endpoint {
    let detected: Date
    let lastSpeech: Date
}

extension AppModel {
    /// Prefix the debug WAV path puts on note bodies so test notes are recognisable.
    static let testNotePrefix = "TEST notch-voice: "

    /// Hotkey or pill click: start listening, cancel it, or barge in over speech.
    func talkPressed() {
        switch state {
        case .call:
            hangUp()
        case .listening:
            cancelListening()
        case .preparing, .sending:
            break
        default:
            speaker.stop()
            startTalking(.microphone, notePrefix: "")
        }
    }

    func escapePressed() {
        if state == .listening {
            cancelListening()
        } else if state.isCall {
            hangUp()
        }
    }

    func startListening(feed: any AudioFeed, notePrefix: String, followUp: Bool = false) {
        guard let vad, let recognizer else {
            show(message: "Models are still loading.", autoHideAfter: 2)
            return
        }
        guard feed is WavFileFeed || microphoneAllowed() else { return }
        stopAutoSpeech()
        collapseTask?.cancel()
        cancelListeningSession()
        isFollowUp = followUp
        let current = listeningGeneration
        transcript = ""
        level = 0
        state = .listening
        EventLog.record("listening_started", ["source": feed is WavFileFeed ? "wav" : "mic"])

        let (stream, continuation) = AsyncStream.makeStream(of: [Float].self, bufferingPolicy: .unbounded)
        audioContinuation = continuation
        feed.start(onSamples: { continuation.yield($0) }, onFailure: { error in
            continuation.finish()
            Task { @MainActor in
                guard self.listeningGeneration == current else { return }
                self.cancelListeningSession()
                self.show(message: error.localizedDescription)
            }
        })
        self.feed = feed
        let silence = settings.silenceSeconds
        let smartTurn = settings.endOfTurn == .smartTurn ? smartTurn : nil
        sessionTask = Task {
            let pipeline = await ListeningPipeline(
                recognizer: recognizer, vad: vad, smartTurn: smartTurn, silenceSeconds: silence,
                minimumSpeechSeconds: followUp ? 0.35 : 0
            )
            guard !Task.isCancelled else { return }
            await runListening(stream, pipeline: pipeline, notePrefix: notePrefix, generation: current)
        }
    }

    private func runListening(
        _ stream: AsyncStream<[Float]>, pipeline: ListeningPipeline, notePrefix: String, generation: Int
    ) async {
        async let primed: Void = watcher.primeCursor(inbox: inbox)
        let endpoint = await consume(stream, with: pipeline, generation: generation)
        guard listeningGeneration == generation else { return }
        audioContinuation?.finish()
        audioContinuation = nil
        stopFeed()
        followUpTask?.cancel()
        let wasFollowUp = isFollowUp
        isFollowUp = false
        await primed
        guard !Task.isCancelled, listeningGeneration == generation else { return }
        guard let endpoint else {
            if wasFollowUp, state == .listening {
                state = .idle
                presentQueuedReply()
            }
            return
        }
        await finishUtterance(pipeline, notePrefix: notePrefix, endpoint: endpoint, generation: generation)
    }

    func cancelListeningSession() {
        questionDictation = nil
        listeningGeneration += 1
        followUpTask?.cancel()
        followUpTask = nil
        isFollowUp = false
        sessionTask?.cancel()
        sessionTask = nil
        audioContinuation?.finish()
        audioContinuation = nil
        stopFeed()
    }

    func cancelListening() {
        cancelListeningSession()
        EventLog.record("listening_cancelled")
        state = .idle
        presentQueuedReply()
    }

    private func stopFeed() {
        guard let feed else { return }
        feed.stop()
        self.feed = nil
        level = 0
        EventLog.record("listening_stopped")
    }

    /// Returns the endpoint when the utterance ended on its own, nil when cancelled or failed.
    private func consume(
        _ stream: AsyncStream<[Float]>, with pipeline: ListeningPipeline, generation: Int
    ) async -> Endpoint? {
        var peak: Float = 0
        for await chunk in stream {
            guard !Task.isCancelled, listeningGeneration == generation else { return nil }
            if peak == 0 {
                EventLog.record("first_audio_in", ["samples": String(chunk.count)])
            }
            level = AudioLevel.normalized(chunk)
            peak = max(peak, level, .leastNonzeroMagnitude)
            do {
                let update = try await pipeline.process(chunk)
                guard !Task.isCancelled, listeningGeneration == generation else { return nil }
                transcript = update.partial
                if isFollowUp, update.speechAccepted {
                    followUpTask?.cancel()
                    followUpTask = nil
                }
                if update.decision == .keepListening {
                    continue
                }
                return endpoint(for: update, peak: peak)
            } catch {
                // Stopping or replacing a listen can throw from the in-flight recognizer.
                guard !Task.isCancelled, listeningGeneration == generation else { return nil }
                show(message: "Listening failed: \(error.localizedDescription)")
                return nil
            }
        }
        return nil
    }

    private func endpoint(for update: ListeningPipeline.Update, peak: Float) -> Endpoint? {
        switch update.decision {
        case .keepListening: return nil
        case .endOfSpeech, .maxLength:
            let detected = Date()
            EventLog.record("turn_ended", [
                "by": update.endedBy ?? "max_length",
                "end_of_turn": settings.endOfTurn.rawValue,
                "pause_ms": String(Int(update.trailingSilenceSeconds * 1000)),
                "audio_ms": String(Int(update.elapsedSeconds * 1000))
            ])
            return Endpoint(detected: detected, lastSpeech: detected - update.trailingSilenceSeconds)
        case .noSpeech:
            EventLog.record("no_speech", ["peak_level": String(format: "%.2f", peak)])
            if !isFollowUp {
                show(message: "Didn't catch that.", autoHideAfter: 2)
            }
            return nil
        }
    }

    private func finishUtterance(
        _ pipeline: ListeningPipeline, notePrefix: String, endpoint: Endpoint, generation: Int
    ) async {
        // A dictated question answer is not on its way to the first mate.
        if questionDictation == nil {
            state = .sending
        }
        do {
            let started = Date()
            let text = try await pipeline.finish()
            guard !Task.isCancelled, listeningGeneration == generation else { return }
            EventLog.record("utterance_transcribed", [
                "model": settings.speechModel.rawValue, "finish_ms": EventLog.milliseconds(from: started)
            ])
            transcript = text
            guard !text.isEmpty else {
                show(message: "Didn't catch that.", autoHideAfter: 2)
                return
            }
            if let reply = questionDictation {
                questionDictation = nil
                state = .idle
                reply(text)
                return
            }
            await route(text, notePrefix: notePrefix, endpoint: endpoint)
        } catch {
            guard !Task.isCancelled, listeningGeneration == generation else { return }
            show(message: "Transcription failed: \(error.localizedDescription)")
        }
    }

    func microphoneAllowed(retry: (@MainActor @Sendable () -> Void)? = nil) -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Task { @MainActor in
                    if granted {
                        if let retry {
                            retry()
                        } else {
                            self.talkPressed()
                        }
                    }
                }
            }
            return false
        default:
            show(message: MicrophoneError.permissionDenied.localizedDescription)
            return false
        }
    }
}
