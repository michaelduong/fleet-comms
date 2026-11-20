//  PhoneModel.swift
//  FleetCommsPhone
//
//  Created by Michael Duong on 11/17/26.

import AVFoundation
import Foundation
import Observation

/// The handset: one link to the Mac, the microphone up, the reply speech down.
@MainActor
@Observable
final class PhoneModel {
    static let shared = PhoneModel()
    let haptics = TalkHaptics()

    enum Link: Equatable {
        case unpaired, connecting, connected, failed(String)
    }

    /// Where the paired Mac can be reached, best first, and what to call it.
    var mac: PairedMac
    @ObservationIgnored var pairing: PhonePairingLink?
    @ObservationIgnored var hostIndex = 0

    var link: Link = .unpaired
    var macState = "idle"
    var macMessage = ""
    var transcript = ""
    var replyText = ""
    var spokenOffset = 0
    var revealMarks: [RevealMark] = []
    var isTalking = false
    var isSpeaking = false
    /// The last sentence the first mate said; the lock-screen card keeps it until the next one.
    var lastSentence = ""
    /// Whether this reply already popped the island open; one alert per reply.
    @ObservationIgnored var alertedReply = false
    var dotStep = 3
    @ObservationIgnored var dotTask: Task<Void, Never>?
    var talkRequestedExternally = false

    @ObservationIgnored let defaults = UserDefaults.standard
    @ObservationIgnored var socket: PhoneSocket?
    @ObservationIgnored let audio = HandsetAudio()
    @ObservationIgnored let live = LiveActivityController()
    @ObservationIgnored let channel = PushToTalkChannel()
    @ObservationIgnored var pttToken: Data?
    @ObservationIgnored var pressedAt: Date?
    @ObservationIgnored var parts: [SpokenPart] = []
    @ObservationIgnored var queuedFrames: Int64 = 0
    @ObservationIgnored var speechEnded = false
    @ObservationIgnored var pendingPart: PendingPart?
    @ObservationIgnored var ticker: DisplayTicker?
    @ObservationIgnored var retry: Task<Void, Never>?

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
        #if DEBUG
            LiveProof.start(self)
        #endif
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
        // Coming on screen is the only moment iOS allows a new card. A dismissed one is forgotten inside.
        updateLive()
    }
}
