//  PhoneModel+Session.swift
//  FleetCommsPhone
//
//  Created by Michael Duong on 11/17/26.

import Foundation

extension PhoneModel {
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
        openSocket(hostList: hostList, port: port, credential: credential)
        scheduleConnectRetry()
    }

    private func openSocket(hostList: [String], port: UInt16, credential: PhoneTLS.Credential) {
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
    }

    /// No answer means no Mac there, or one that does not hold this phone's key; try its next address.
    private func scheduleConnectRetry() {
        let attempt = socket
        retry = Task {
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled, link == .connecting else { return }
            attempt?.onClose = nil
            attempt?.close()
            hostIndex += 1
            // Pairing is one-shot, so try every address in the code before giving up.
            if let pairing, hostIndex < pairing.hosts.count {
                return connect()
            }
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

    #if DEBUG
        /// Feeds one Mac message for the off-screen reply proof. Not called in a release build.
        func prove(_ message: PhoneMessage) {
            handle(message)
        }

        var liveProof: String {
            live.proofLine
        }
    #endif

    private func applyState(_ message: PhoneMessage) {
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
        updateLive()
    }

    private func handle(_ message: PhoneMessage) {
        switch message.kind {
        case .paired: finishPairing(message)
        case .ready:
            retry?.cancel()
            link = .connected
            sendPTTToken()
            Task { await channel.join() }
        case .state: applyState(message)
        case .transcript:
            transcript = message.text ?? ""
            updateLive()
        case .speech: beginSpeech(message.text ?? "")
        case .part: pendingPart = PendingPart(
                start: message.start ?? 0,
                length: message.length ?? 0,
                words: message.words
            )
        case .speechEnd:
            speechEnded = true
            finishIfDone()
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

    func sendPTTToken() {
        guard isConnected, let pttToken else { return }
        var message = PhoneMessage(.pttToken)
        message.text = pttToken.map { String(format: "%02x", $0) }.joined()
        socket?.send(message)
    }

    private func release() {
        haptics.sent()
        socket?.send(PhoneMessage(.release))
        endTalking()
        updateLive()
    }

    private func endTalking() {
        guard isTalking else { return }
        isTalking = false
        pressedAt = nil
        haptics.cancelHold()
        audio.stopMic()
    }

    func startAfterConnect() async {
        for _ in 0 ..< 20 where !isConnected {
            try? await Task.sleep(for: .milliseconds(250))
        }
        pressDown()
    }
}
