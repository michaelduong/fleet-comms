//  PhoneModel+Speech.swift
//  FleetCommsPhone
//
//  Created by Michael Duong on 11/17/26.

import AVFoundation
import Foundation
import QuartzCore
import UIKit

extension PhoneModel {
    func updateLive() {
        let phase = LiveCard.phase(isTalking: isTalking, isSpeaking: isSpeaking, macState: macState)
        if phase == .speaking {
            stopDots()
            let sentence = LiveCard.sentence(phase: phase, reply: replyText, offset: spokenOffset, held: lastSentence)
            lastSentence = sentence
        }
        let onScreen = UIApplication.shared.applicationState == .active
        if phase == .listening || phase == .thinking {
            startDots()
        } else {
            stopDots()
        }
        let alert = LiveCard.shouldAlert(
            phase: phase, alreadyAlerted: alertedReply, sentence: lastSentence,
            appOnScreen: onScreen,
            unlocked: UIApplication.shared.isProtectedDataAvailable
        )
        if alert {
            alertedReply = true
        }
        // Idle still updates the card: ending it would force the reply to open a new one off screen.
        live.update(.init(phase: phase, sentence: lastSentence, dots: dotStep), alert: alert, canStart: onScreen)
    }

    private func startDots() {
        guard dotTask == nil else { return }
        dotStep = 1
        dotTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(600))
                guard let self, !Task.isCancelled else { return }
                dotStep = dotStep % 3 + 1
                updateLive()
            }
        }
    }

    private func stopDots() {
        dotTask?.cancel()
        dotTask = nil
    }

    func beginSpeech(_ text: String) {
        flushSpeech()
        replyText = text
        alertedReply = false
        spokenOffset = 0
        revealMarks = []
        isSpeaking = true
        speechEnded = false
        ticker = DisplayTicker { [weak self] in self?.updateProgress() }
    }

    func play(_ data: Data) {
        // A part that arrives after the queue ran dry starts now, not where the queue would have been.
        queuedFrames = max(queuedFrames, audio.playedFrames)
        let samples = PhoneLink.samples(data)
        if let part = pendingPart {
            let base = Int(queuedFrames)
            parts.append(SpokenPart(
                range: part.start ..< part.start + part.length,
                startFrame: queuedFrames,
                frames: Int64(samples.count),
                words: part.words?
                    .map { PhoneWord(start: part.start + $0.start, length: $0.length, sample: base + $0.sample) }
            ))
        }
        queuedFrames += Int64(samples.count)
        audio.play(samples) { [weak self] in
            Task { @MainActor in self?.playbackDrained() }
        }
    }

    func playbackDrained() {
        finishIfDone()
    }

    func finishIfDone() {
        guard SpeechEnd.shouldEnd(speechEnded: speechEnded, pendingBuffers: audio.pendingBuffers) else { return }
        isSpeaking = false
        ticker?.stop()
        ticker = nil
        spokenOffset = replyText.utf16.count
        revealMarks.append(RevealMark(end: spokenOffset, time: CACurrentMediaTime() - 1))
        updateLive()
    }

    func updateProgress() {
        // What the speaker plays now was heard `outputLatency` ago, so show words against what is audible.
        let latency = Int64(AVAudioSession.sharedInstance().outputLatency * PhoneLink.speechRate)
        let frame = max(0, audio.playedFrames - latency)
        guard let part = parts.last(where: { $0.startFrame <= frame }) else { return }
        let offset: Int
        if let words = part.words {
            offset = SpokenReveal.offset(words: words, playedSamples: Int(frame)) ?? part.range.lowerBound
        } else {
            let fraction = Double(frame - part.startFrame) / Double(max(1, part.frames))
            offset = SpokenReveal.guessOffset(in: replyText, range: part.range, fraction: fraction)
        }
        guard offset > spokenOffset else { return }
        spokenOffset = offset
        revealMarks.append(RevealMark(end: offset, time: CACurrentMediaTime()))
        updateLive()
    }

    func flushSpeech() {
        audio.stopPlayback()
        ticker?.stop()
        ticker = nil
        parts = []
        queuedFrames = 0
        pendingPart = nil
        speechEnded = false
        isSpeaking = false
    }
}
