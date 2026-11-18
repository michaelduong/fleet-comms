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
    private let haptics = TalkHaptics()

    enum Link: Equatable {
        case unpaired, connecting, connected, failed(String)
    }

    /// Where the paired Mac can be reached, best first, and what to call it.
    private(set) var mac: PairedMac
    @ObservationIgnored private var pairing: PhonePairingLink?
    @ObservationIgnored private var hostIndex = 0

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
    @ObservationIgnored private let live = LiveActivityController()
    @ObservationIgnored private let channel = PushToTalkChannel()
    @ObservationIgnored private var pttToken: Data?
    @ObservationIgnored private var pressedAt: Date?
    @ObservationIgnored private var parts: [SpokenPart] = []
    @ObservationIgnored private var queuedFrames: Int64 = 0
    @ObservationIgnored private var pendingPart: (start: Int, length: Int)?
    @ObservationIgnored private var progressTimer: Timer?
    @ObservationIgnored private var retry: Task<Void, Never>?

    init() {
        mac = PairedMac(defaults: defaults)
        audio.onMicSamples = { [weak self] samples in
            Task { @MainActor in self?.socket?.sendAudio(samples) }
        }
        channel.onToken = { [weak self] token in
            self?.pttToken = token
            self?.sendPTTToken()
        }
        channel.onTalkBegan = { [weak self] in self?.pressDown() }
        channel.onTalkEnded = { [weak self] in self?.pressUp(force: true) }
        channel.onIncomingReply = { [weak self] in self?.appBecameActive() }
    }

    var isPaired: Bool {
        mac.isPaired
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

    /// Reads a scanned or pasted link and pairs with the Mac it names; false when the text is not a pairing link.
    @discardableResult
    func pair(with text: String) -> Bool {
        guard let link = PhonePairingLink(text) else { return false }
        pairing = link
        hostIndex = 0
        connect()
        return true
    }

    func connect() {
        retry?.cancel()
        socket?.onClose = nil
        socket?.close()
        let credential: PhoneTLS.Credential
        let hostList: [String]
        let port: UInt16
        if let pairing {
            credential = .init(identity: "pair-" + pairing.id, key: pairing.key)
            hostList = pairing.hosts
            port = pairing.port
        } else if let own = mac.credential, mac.isPaired {
            credential = own
            hostList = mac.hosts
            port = PhoneLink.port
        } else {
            return link = .unpaired
        }
        link = .connecting
        let host = hostList[hostIndex % hostList.count]
        let socket = PhoneSocket.client(
            host: host.trimmingCharacters(in: .whitespaces),
            port: port,
            credential: credential
        )
        socket.onMessage = { [weak self] message in Task { @MainActor in self?.handle(message) } }
        socket.onAudio = { [weak self] data in Task { @MainActor in self?.play(data) } }
        socket.onClose = { [weak self, weak socket] in
            Task { @MainActor in
                guard let self, socket === self.socket else { return }
                self.lost()
            }
        }
        self.socket = socket
        let pairingID = pairing?.id
        let phoneID = mac.phoneID
        socket.start {
            var hello = PhoneMessage(pairingID == nil ? .hello : .pair)
            hello.token = pairingID ?? phoneID
            socket.send(hello)
        }
        // No answer means no Mac there, or one that does not hold this phone's key; try its next address.
        retry = Task {
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled, link == .connecting else { return }
            socket.onClose = nil
            socket.close()
            hostIndex += 1
            link = .failed(pairing == nil
                ? "The Mac did not answer. Check that Tailscale is on, or pair again."
                : "Could not reach the Mac. Check the code is still showing and try again.")
        }
    }

    private func finishPairing(_ message: PhoneMessage) {
        guard let pairing, let id = message.token, let key = message.text.flatMap(Base64URL.decode) else { return }
        mac.save(link: pairing, phoneID: id, key: key, defaults: defaults)
        self.pairing = nil
        hostIndex = 0
        connect()
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
        case .paired: finishPairing(message)
        case .ready:
            retry?.cancel()
            link = .connected
            sendPTTToken()
            Task { await channel.join() }
        case .state:
            let previous = macState
            macState = message.state ?? "idle"
            macMessage = message.text ?? ""
            if previous == "listening", macState == "sending" {
                haptics.sentByMac()
            } else if macState == "message", previous == "listening" || previous == "sending" {
                haptics.warning()
            }
            if macState != "listening" {
                endTalking()
            }
        case .transcript:
            transcript = message.text ?? ""
            updateLive()
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
        guard isConnected else { return haptics.error() }
        if isTalking {
            return release()
        }
        flushSpeech()
        socket?.send(PhoneMessage(.stopSpeech))
        transcript = ""
        replyText = ""
        guard audio.startMic() else { return }
        isTalking = true
        haptics.opened()
        updateLive()
        pressedAt = Date()
        socket?.send(PhoneMessage(.start))
    }

    func pressUp(force: Bool = false) {
        guard isTalking else { return }
        if force {
            return release()
        }
        guard let pressedAt else { return }
        self.pressedAt = nil
        haptics.cancelHold()
        if Date().timeIntervalSince(pressedAt) >= PhoneLink.holdSeconds {
            release()
        }
    }

    func cancelTalking() {
        guard isTalking else { return }
        socket?.send(PhoneMessage(.cancel))
        endTalking()
    }

    private func sendPTTToken() {
        guard isConnected, let pttToken else { return }
        var message = PhoneMessage(.pttToken)
        message.text = pttToken.map { String(format: "%02x", $0) }.joined()
        socket?.send(message)
    }

    private func updateLive() {
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

    private func release() {
        haptics.sent()
        socket?.send(PhoneMessage(.release))
        endTalking()
    }

    private func endTalking() {
        guard isTalking else { return }
        isTalking = false
        pressedAt = nil
        haptics.cancelHold()
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
        updateLive()
    }

    private func updateProgress() {
        let frame = audio.playedFrames
        guard let part = parts.last(where: { $0.startFrame <= frame }) else { return }
        let fraction = min(1, max(0, Double(frame - part.startFrame) / Double(max(1, part.frames))))
        spokenOffset = part.range.lowerBound + Int(Double(part.range.count) * fraction)
        updateLive()
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
