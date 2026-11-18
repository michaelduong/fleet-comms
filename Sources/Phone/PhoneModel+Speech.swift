//  PhoneModel+Speech.swift
//  FleetCommsPhone
//
//  Created by Michael Duong on 11/17/26.

import AVFoundation
import Foundation
import QuartzCore

extension PhoneModel {
    func updateLive() {
        let phase: CommsActivityAttributes.ContentState.Phase = isTalking ? .listening
            : isSpeaking ? .speaking : (macState == "thinking" || macState == "sending") ? .thinking : .idle
        guard phase != .idle || !replyText.isEmpty || !transcript.isEmpty else { return live.end() }
        let utf16 = Array(replyText.utf16)
        let upTo = min(utf16.count, spokenOffset)
        let sentence: String = {
            guard isSpeaking else { return "" }
            let before = String(utf16CodeUnits: Array(utf16[..<upTo]), count: upTo)
            let start = before.lastIndex(where: { ".!?".contains($0) }).map { before.index(after: $0) } ?? before
                .startIndex
            let rest = String(utf16CodeUnits: Array(utf16[upTo...]), count: utf16.count - upTo)
            let end = rest.firstIndex(where: { ".!?".contains($0) }).map { rest.index(after: $0) } ?? rest.endIndex
            return (before[start...] + rest[..<end]).trimmingCharacters(in: .whitespaces)
        }()
        live.update(.init(phase: phase, words: transcript, sentence: sentence))
    }

    func beginSpeech(_ text: String) {
        flushSpeech()
        replyText = text
        spokenOffset = 0
        revealMarks = []
        isSpeaking = true
        ticker = DisplayTicker { [weak self] in self?.updateProgress() }
    }

    func play(_ data: Data) {
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
        guard audio.pendingBuffers == 0 else { return }
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
        isSpeaking = false
    }
}
