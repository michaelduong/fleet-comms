//  RealtimeCall.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation

@MainActor
protocol RealtimeCallDelegate: AnyObject {
    func call(_ call: RealtimeCall, phase: CallPhase)
    func call(_ call: RealtimeCall, level: Float)
    /// The owner's words, or the model's as it speaks them; shown on screen, never logged.
    func call(_ call: RealtimeCall, text: String)
    func call(_ call: RealtimeCall, playback: SpeechPlayback)
    /// Files the owner's request as a note; returns its id, or nil when it could not be sent.
    func call(_ call: RealtimeCall, handOff request: String, endpoint: Endpoint) async -> String?
    func call(_ call: RealtimeCall, endedWith error: RealtimeError?)
}

extension RealtimeCallDelegate {
    func call(_ call: RealtimeCall, playback: SpeechPlayback) {}
}

/// One hands-free conversation with a realtime model: opened by the hotkey, closed by the hotkey,
/// Esc, or the configured quiet window after playback. Server turn detection ends each turn; talking over the model
/// stops its audio at once.
@MainActor
final class RealtimeCall {
    enum Source {
        case microphone
        case wav(URL)
    }

    let outreach: RealtimeOutreach?
    var outreachPlayback = false
    var outreachDeadline: Task<Void, Never>?

    let idleHangUp: TimeInterval
    /// About -39 dBFS on the level meter's scale: above room noise, below quiet speech.
    nonisolated static let speechLevel: Float = 0.35

    let provider: RealtimeProvider
    let source: Source
    weak var delegate: RealtimeCallDelegate?

    let voice: String
    let silenceMs: Int
    let lookup: MessengerLookup?
    /// Rebuilt as each turn starts, so a fleet summary that lands mid-call reaches the model.
    let instructions: @MainActor () -> String
    var sentInstructions = ""
    var socket: RealtimeSocket?
    var audio: RealtimeAudio?
    var feed: WavFileFeed?
    var eventTask: Task<Void, Never>?
    var idleTask: Task<Void, Never>?
    /// When audio last sounded like speech, measured here because the providers count
    /// `audio_end_ms` from different origins.
    let lastSpeech = ThreadSafeBox<Date?>(nil)
    let startedAt = Date()
    var ended = false
    var turns = 0
    var lastActivity = Date()

    var turn: RealtimeTurn?
    var responseActive = false
    var pendingTools = 0
    var toolResponsePending = false
    #if DEBUG
        var observeToolCall: ((String, String) -> Void)?
    #endif
    var ownerTalking = false
    var audioQueued = false
    var playingItem: (id: String, since: Date)?
    var spoken = ""
    var speechID = UUID()
    var announcements: [ReplyWatcher.Delivery] = []
    /// The reply being read, until its first audio is logged.
    var announcing: ReplyWatcher.Delivery?

    init(
        provider: RealtimeProvider, voice: String, source: Source, silenceSeconds: Double,
        idleHangUp: TimeInterval = 10, outreach: RealtimeOutreach? = nil, dataDirectory: URL? = nil,
        instructions: @escaping @MainActor () -> String
    ) {
        self.provider = provider
        self.voice = voice
        self.source = source
        self.idleHangUp = idleHangUp
        self.outreach = outreach
        lookup = dataDirectory.map { MessengerLookup(dataDirectory: $0) }
        silenceMs = Int(silenceSeconds * 1000)
        self.instructions = instructions
    }

    func start() {
        delegate?.call(self, phase: .connecting)
        if outreach != nil {
            watchOutreach(seconds: 12)
        }
        eventTask = Task {
            let started = Date()
            do {
                let socket = try await RealtimeSocket.connect(provider)
                guard !ended else { return socket.close() }
                self.socket = socket
                EventLog.record("realtime_connected", ["lane": provider.id, "ms": EventLog.milliseconds(from: started)])
                if let outreach {
                    startOutputAudio()
                    socket.send(OutreachWire.sessionUpdate(voice: voice))
                    socket.send(RealtimeWire.userText(outreach.readingText))
                    socket.send(RealtimeWire.createResponse())
                    delegate?.call(self, text: outreach.reply.text)
                } else {
                    beginConversation()
                }
                for try await event in socket.events() {
                    handle(event)
                }
            } catch {
                guard !ended else { return }
                let failure = RealtimeError.from(error)
                EventLog.record("realtime_failed", [
                    "lane": provider.id, "reason": failure.code, "ms": EventLog.milliseconds(from: started)
                ])
                end(failure)
            }
        }
    }

    /// Ends the call; `error` nil means the owner or the idle timer hung up.
    func end(_ error: RealtimeError? = nil, reason: String = "hung_up") {
        guard !ended else { return }
        ended = true
        idleTask?.cancel()
        outreachDeadline?.cancel()
        eventTask?.cancel()
        feed?.stop()
        audio?.stop()
        socket?.close()
        EventLog.record("realtime_call_ended", [
            "lane": provider.id, "reason": error?.code ?? reason, "turns": String(turns),
            "seconds": String(Int(Date().timeIntervalSince(startedAt))),
            "quiet_seconds": String(format: "%.2f", quietSeconds()),
            "idle_timeout_seconds": String(Int(idleHangUp))
        ])
        delegate?.call(self, endedWith: error)
    }

    func updateInstructionsIfChanged() {
        let current = instructions()
        guard current != sentInstructions, let socket else { return }
        sentInstructions = current
        socket.send(RealtimeWire.sessionUpdate(.init(
            provider: provider, voice: voice, instructions: current, silenceMs: silenceMs
        )))
    }

    /// Reads a first-mate reply through the model once it is not talking.
    func announce(_ delivery: ReplyWatcher.Delivery) {
        announcements.append(delivery)
        announceIfQuiet()
    }

    func startAudio(_ socket: RealtimeSocket) {
        let lastSpeech = lastSpeech
        let send: @Sendable ([Float]) -> Void = { samples in
            if AudioLevel.normalized(samples) > Self.speechLevel {
                lastSpeech.value = Date()
            }
            socket.send(RealtimeWire.appendAudio(RealtimePCM.encode(samples)))
        }
        let audio = RealtimeAudio { [weak self] in
            Task { @MainActor in self?.drained() }
        }
        self.audio = audio
        let failed: @Sendable (Error) -> Void = { [weak self] _ in
            Task { @MainActor in self?.end(.audioFailed) }
        }
        switch source {
        case .microphone:
            audio.start(onInput: { [weak self] samples in
                send(samples)
                let level = AudioLevel.normalized(samples)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    delegate?.call(self, level: level)
                }
            }, onFailure: failed)
        case let .wav(url):
            audio.start(onInput: nil, onFailure: failed)
            let feed = WavFileFeed(url: url)
            self.feed = feed
            feed.start(onSamples: { send(RealtimePCM.upsample16kTo24k($0)) }, onFailure: failed)
        }
    }

    func quietSeconds(at now: Date = Date()) -> TimeInterval {
        now.timeIntervalSince(max(lastActivity, lastSpeech.value ?? lastActivity))
    }

    func checkForIdle(at now: Date = Date()) {
        guard !ended, outreach == nil || outreach?.completed == true,
              !responseActive, pendingTools == 0, !audioQueued, !ownerTalking else { return }
        if quietSeconds(at: now) >= idleHangUp {
            end(reason: "idle")
        }
    }

    func watchForIdle() {
        idleTask = Task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(100))
                } catch {
                    return
                }
                checkForIdle()
            }
        }
    }
}

/// Timing for one owner turn: from end of speech to the model's first audio.
struct RealtimeTurn {
    let id = String(UUID().uuidString.prefix(8))
    let stoppedAt = Date()
    /// When the owner actually stopped talking, before the silence wait.
    let lastSpeech: Date
    var firstAudioLogged = false

    var endpoint: Endpoint {
        Endpoint(detected: stoppedAt, lastSpeech: lastSpeech)
    }
}
