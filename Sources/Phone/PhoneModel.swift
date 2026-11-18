//  PhoneModel.swift
//  FleetCommsPhone
//
//  Created by Michael Duong on 11/17/26.

import AVFoundation
import Foundation
import Observation

/// The handset: one link to the Mac, the microphone up, the reply speech down.
/// Where one sentence of the reply sits in the text and in the queued audio.
struct SpokenPart {
    let range: Range<Int>
    let startFrame: Int64
    let frames: Int64
}

@MainActor
@Observable
final class PhoneModel {
    static let shared = PhoneModel()

    enum Link: Equatable {
        case unpaired, connecting, connected, failed(String)
    }

    var host: String {
        didSet { defaults.set(host, forKey: "host") }
    }

    var token: String {
        didSet { defaults.set(token, forKey: "token") }
    }

    private(set) var link: Link = .unpaired
    private(set) var macState = "idle"
    private(set) var macMessage = ""
    private(set) var transcript = ""
    private(set) var replyText = ""
    private(set) var spokenOffset = 0
    private(set) var isTalking = false
    private(set) var isSpeaking = false
    var talkRequestedExternally = false

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var socket: PhoneSocket?
    @ObservationIgnored private let audio = HandsetAudio()
    @ObservationIgnored private var pressedAt: Date?
    @ObservationIgnored private var parts: [SpokenPart] = []
    @ObservationIgnored private var queuedFrames: Int64 = 0
    @ObservationIgnored private var pendingPart: (start: Int, length: Int)?
    @ObservationIgnored private var progressTimer: Timer?
    @ObservationIgnored private var retry: Task<Void, Never>?

    init() {
        host = defaults.string(forKey: "host") ?? ""
        token = defaults.string(forKey: "token") ?? ""
        audio.onMicSamples = { [weak self] samples in
            Task { @MainActor in self?.socket?.sendAudio(samples) }
        }
    }

    var isPaired: Bool {
        !host.isEmpty && !token.isEmpty
    }

    var isConnected: Bool {
        link == .connected
    }

    // MARK: - Link

    func appBecameActive() {
        if isPaired, !isConnected, link != .connecting {
            connect()
        }
        if talkRequestedExternally {
            talkRequestedExternally = false
            Task { await startAfterConnect() }
        }
    }

    func connect() {
        retry?.cancel()
        socket?.onClose = nil
        socket?.close()
        guard isPaired else { return link = .unpaired }
        link = .connecting
        let socket = PhoneSocket.client(host: host.trimmingCharacters(in: .whitespaces), port: PhoneLink.port)
        socket.onMessage = { [weak self] message in Task { @MainActor in self?.handle(message) } }
        socket.onAudio = { [weak self] data in Task { @MainActor in self?.play(data) } }
        socket.onClose = { [weak self, weak socket] in
            Task { @MainActor in
                guard let self, socket === self.socket else { return }
                self.lost()
            }
        }
        self.socket = socket
        let token = token
        socket.start {
            var hello = PhoneMessage(.hello)
            hello.token = token
            socket.send(hello)
        }
        // The Mac answers a good token with `ready`; no answer means no Mac there, or a wrong code.
        retry = Task {
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled, link == .connecting else { return }
            socket.onClose = nil
            socket.close()
            link = .failed("The Mac did not answer. Check the host, the pairing code and that Tailscale is on.")
        }
    }

    func disconnect() {
        retry?.cancel()
        socket?.onClose = nil
        socket?.close()
        socket = nil
        endTalking()
        flushSpeech()
        link = isPaired ? .failed("Disconnected.") : .unpaired
    }

    private func lost() {
        socket = nil
        endTalking()
        flushSpeech()
        link = .failed("Connection lost.")
        retry = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, !isConnected else { return }
            connect()
        }
    }

    private func handle(_ message: PhoneMessage) {
        switch message.kind {
        case .ready:
            retry?.cancel()
            link = .connected
        case .state:
            macState = message.state ?? "idle"
            macMessage = message.text ?? ""
            if macState != "listening" {
                endTalking()
            }
        case .transcript: transcript = message.text ?? ""
        case .speech: beginSpeech(message.text ?? "")
        case .part: pendingPart = (message.start ?? 0, message.length ?? 0)
        case .speechEnd: break
        case .stopSpeech: flushSpeech()
        default: break
        }
    }

    // MARK: - Talking

    /// Press: open the mic. Release after a hold sends at once; a quick tap stays open for the Mac's
    /// pause detection, and tapping again while open sends now.
    func pressDown() {
        guard isConnected else { return }
        if isTalking {
            return release()
        }
        flushSpeech()
        socket?.send(PhoneMessage(.stopSpeech))
        transcript = ""
        replyText = ""
        guard audio.startMic() else { return }
        isTalking = true
        pressedAt = Date()
        socket?.send(PhoneMessage(.start))
    }

    func pressUp() {
        guard isTalking, let pressedAt else { return }
        self.pressedAt = nil
        if Date().timeIntervalSince(pressedAt) >= PhoneLink.holdSeconds {
            release()
        }
    }

    func cancelTalking() {
        guard isTalking else { return }
        socket?.send(PhoneMessage(.cancel))
        endTalking()
    }

    private func release() {
        socket?.send(PhoneMessage(.release))
        endTalking()
    }

    private func endTalking() {
        guard isTalking else { return }
        isTalking = false
        pressedAt = nil
        audio.stopMic()
    }

    private func startAfterConnect() async {
        for _ in 0 ..< 20 where !isConnected {
            try? await Task.sleep(for: .milliseconds(250))
        }
        pressDown()
    }
}

extension PhoneModel {
    private func beginSpeech(_ text: String) {
        flushSpeech()
        replyText = text
        spokenOffset = 0
        isSpeaking = true
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateProgress() }
        }
    }

    private func play(_ data: Data) {
        let samples = PhoneLink.samples(data)
        if let part = pendingPart {
            parts.append(SpokenPart(
                range: part.start ..< part.start + part.length,
                startFrame: queuedFrames,
                frames: Int64(samples.count)
            ))
        }
        queuedFrames += Int64(samples.count)
        audio.play(samples) { [weak self] in
            Task { @MainActor in self?.playbackDrained() }
        }
    }

    private func playbackDrained() {
        guard audio.pendingBuffers == 0 else { return }
        isSpeaking = false
        progressTimer?.invalidate()
        spokenOffset = replyText.utf16.count
    }

    private func updateProgress() {
        let frame = audio.playedFrames
        guard let part = parts.last(where: { $0.startFrame <= frame }) else { return }
        let fraction = min(1, max(0, Double(frame - part.startFrame) / Double(max(1, part.frames))))
        spokenOffset = part.range.lowerBound + Int(Double(part.range.count) * fraction)
    }

    private func flushSpeech() {
        audio.stopPlayback()
        progressTimer?.invalidate()
        parts = []
        queuedFrames = 0
        pendingPart = nil
        isSpeaking = false
    }
}
