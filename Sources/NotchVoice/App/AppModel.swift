//  AppModel.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import FluidAudio
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    let settings: AppSettings

    var state: NotchState = .idle {
        didSet {
            hotkeys?.setEscapeEnabled(state.claimsEscape)
        }
    }

    var level: Float = 0
    var transcript = ""
    var speechPlayback: SpeechPlayback?
    var pendingReplies = 0
    var questionDictation: ((String) -> Void)?
    let questions = AskQuestionStore()

    @ObservationIgnored var hotkeys: HotkeyCenter?
    @ObservationIgnored let speaker = ReplySpeaker()
    @ObservationIgnored let watcher = ReplyWatcher()
    @ObservationIgnored var sessionReplyTask: Task<Void, Never>?
    @ObservationIgnored var autoSpeakReplies: [SessionReplyReader.Reply] = []
    @ObservationIgnored var isAutoSpeaking = false
    @ObservationIgnored var autoSpeakID: UUID?
    @ObservationIgnored var outreachSourceOverride: RealtimeCall.Source?
    @ObservationIgnored var vad: VadManager?
    @ObservationIgnored var recognizer: (any SpeechRecognizer)?
    /// Loaded only once Smart Turn is chosen as the end-of-turn decider.
    @ObservationIgnored var smartTurn: SmartTurn?
    @ObservationIgnored var feed: (any AudioFeed)?
    @ObservationIgnored var sessionTask: Task<Void, Never>?
    @ObservationIgnored var queuedReplies: [ReplyWatcher.Delivery] = []
    @ObservationIgnored var followUpTask: Task<Void, Never>?
    @ObservationIgnored var followUpFeed: () -> any AudioFeed = { MicrophoneFeed() }
    @ObservationIgnored var isFollowUp = false
    @ObservationIgnored var listeningGeneration = 0
    @ObservationIgnored var audioContinuation: AsyncStream<[Float]>.Continuation?
    @ObservationIgnored var collapseTask: Task<Void, Never>?
    @ObservationIgnored var loadedModel: (SpeechModelChoice, Double)?
    @ObservationIgnored var loadTask: Task<Void, Never>?
    @ObservationIgnored private var modelNote: String?
    /// Where the pointer really is, asked at dismissal time: a hover flag alone goes stale when the
    /// card is hidden underneath the pointer, which then never sees it leave.
    @ObservationIgnored var pointerOverPill: () -> Bool = { false }
    @ObservationIgnored var assistant: ClaudeAssistant?
    @ObservationIgnored let fleet = FleetContext()
    @ObservationIgnored var conversation = AssistantConversation()
    @ObservationIgnored var call: RealtimeCall?
    @ObservationIgnored var callNotePrefix = ""

    var inbox: FirstmateInbox {
        FirstmateInbox(home: settings.firstmateHome, script: settings.resolvedInboxScript)
    }

    var modelsReady: Bool {
        vad != nil && recognizer != nil
    }

    @ObservationIgnored private(set) var isLoading = false

    init(settings: AppSettings) {
        self.settings = settings
        speaker.onProgress = { [weak self] in self?.speechPlayback = $0 }
        speaker.speed = { [weak settings] in settings?.speechSpeed ?? .brisk }
        watcher.onReply = { [weak self] in self?.receive($0) }
        watcher.onTimeout = { [weak self] _ in self?.replyTimedOut() }
    }

    // MARK: - Models

    func prepareModels() {
        loadTask?.cancel()
        loadTask = Task { await loadModels() }
    }

    private func loadModels() async {
        isLoading = true
        defer { isLoading = false }
        let sink: ModelLoader.ProgressSink = { [weak self] progress in
            Task { @MainActor in self?.showPreparing(progress) }
        }
        do {
            if vad == nil {
                vad = try await ModelLoader.loadVad(progress: sink)
            }
            try await reloadRecognizerIfNeeded(progress: sink)
            await loadSmartTurnIfNeeded(progress: sink)
            if !speaker.isLoaded {
                showPreparing(.init(step: "Voice", fraction: nil))
                try await speaker.load(voiceID: settings.voiceID, progress: voiceProgress)
            }
            if case .preparing = state {
                state = .idle
            }
            if let modelNote {
                self.modelNote = nil
                show(message: modelNote, autoHideAfter: 8)
            }
            EventLog.record("models_ready", ["model": settings.speechModel.rawValue])
        } catch {
            Log.speech.error("Model load failed: \(error.localizedDescription, privacy: .public)")
            show(message: "Could not load models: \(error.localizedDescription)")
        }
    }

    private func reloadRecognizerIfNeeded(progress: @escaping ModelLoader.ProgressSink) async throws {
        let wanted = (settings.speechModel, settings.silenceSeconds)
        if let loadedModel, loadedModel == wanted, recognizer != nil {
            return
        }
        recognizer = nil
        do {
            recognizer = try await ModelLoader.loadRecognizer(wanted.0, silenceSeconds: wanted.1, progress: progress)
        } catch where wanted.0 == .fluidSpeechPro {
            Log.speech.error("Fluid Speech Pro failed: \(error.localizedDescription, privacy: .public)")
            EventLog.record("speech_model_fallback", ["model": wanted.0.rawValue])
            modelNote = "Fluid Speech Pro didn't load (\(error.localizedDescription)). Using Parakeet TDT v2."
            recognizer = try await ModelLoader.loadRecognizer(
                .parakeetTdtV2, silenceSeconds: wanted.1, progress: progress
            )
        }
        loadedModel = wanted
    }

    /// A Smart Turn that fails to download or load leaves the silence threshold in charge.
    private func loadSmartTurnIfNeeded(progress: @escaping ModelLoader.ProgressSink) async {
        guard settings.endOfTurn == .smartTurn, smartTurn == nil else { return }
        do {
            smartTurn = try await ModelLoader.loadSmartTurn(progress: progress)
        } catch {
            Log.speech.error("Smart Turn failed: \(error.localizedDescription, privacy: .public)")
            EventLog.record("smart_turn_fallback")
            modelNote = "Smart Turn didn't load (\(error.localizedDescription)). Ending turns on silence."
        }
    }

    private func showPreparing(_ progress: ModelLoader.Progress) {
        switch state {
        case .idle, .preparing:
            state = .preparing(activity: progress.activity, step: progress.step, fraction: progress.fraction)
        default: break
        }
    }

    private var voiceProgress: ModelStore.Progress {
        { [weak self] fraction, activity in
            Task { @MainActor in
                guard let self else { return }
                if fraction == 1 {
                    if case .preparing = self.state {
                        self.state = .idle
                    }
                } else {
                    self.showPreparing(.init(step: "Voice", fraction: fraction, activity: activity))
                }
            }
        }
    }

    func voiceChanged() {
        Task {
            do {
                try await speaker.setVoice(settings.voiceID, progress: voiceProgress)
                if case .preparing = state {
                    state = .idle
                }
            } catch {
                show(message: "Could not load voice: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Presentation

    func dismiss() {
        autoSpeakReplies.removeAll()
        stopAutoSpeech()
        cancelListeningSession()
        speaker.stop()
        collapseTask?.cancel()
        state = .idle
        presentQueuedReply()
    }

    func show(message: String, autoHideAfter seconds: Double? = nil) {
        collapseTask?.cancel()
        state = .message(message)
        let seconds = seconds ?? settings.autoDismissSeconds
        guard seconds > 0 else { return }
        collapse(after: seconds)
    }

    func collapse(after seconds: Double, onCollapse: (() -> Void)? = nil) {
        collapseTask?.cancel()
        let shown = state
        collapseTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, state == shown else { return }
            if case .reply(_, false, _) = shown, pointerOverPill() {
                collapse(after: seconds, onCollapse: onCollapse)
                return
            }
            state = .idle
            onCollapse?()
            presentQueuedReply()
        }
    }

    /// Passive listening always has a deadline; a silent reply stays only while the pointer is on it.
    func scheduleAutoDismiss() {
        if settings.keepListeningAfterReply, settings.autoDismissSeconds > 0 {
            scheduleFollowUp()
            return
        }
        guard settings.autoDismissSeconds > 0 else { return }
        let scheduled = Date()
        collapse(after: settings.autoDismissSeconds) {
            EventLog.record("auto_dismissed", ["after_ms": EventLog.milliseconds(from: scheduled)])
        }
    }

    /// The pointer leaving a silent reply restarts its delay; arriving needs nothing, since the
    /// delay checks the pointer itself before it dismisses.
    func setPillHovered(_ hovering: Bool) {
        guard !hovering, case .reply(_, false, _) = state else { return }
        scheduleAutoDismiss()
    }
}
