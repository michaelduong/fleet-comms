//  AppSettings.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
    enum Change {
        case speechModel
        case voice
        case hotkey
        case assistant
        case fleetSchedule
        case refreshFleet
        case voiceLane
        case followUp
        case autoSpeak
        case placement
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored var onChange: ((Change) -> Void)?

    var speechModel: SpeechModelChoice {
        didSet {
            defaults.set(speechModel.rawValue, forKey: Key.speechModel)
            onChange?(.speechModel)
        }
    }

    var voiceID: String {
        didSet {
            defaults.set(voiceID, forKey: Key.voice)
            onChange?(.voice)
        }
    }

    var speechSpeed: SpeechSpeed {
        didSet { defaults.set(speechSpeed.rawValue, forKey: Key.speechSpeed) }
    }

    var keepListeningAfterReply: Bool {
        didSet {
            defaults.set(keepListeningAfterReply, forKey: Key.keepListeningAfterReply)
            onChange?(.followUp)
        }
    }

    var hotkey: HotkeyPreset {
        didSet {
            defaults.set(hotkey.rawValue, forKey: Key.hotkey)
            onChange?(.hotkey)
        }
    }

    var silenceSeconds: Double {
        // The realtime model's end-of-utterance debounce is fixed at load, so this reloads it.
        didSet {
            defaults.set(silenceSeconds, forKey: Key.silenceSeconds)
            onChange?(.speechModel)
        }
    }

    /// Smart Turn's model loads with the others, so choosing it prepares the models again.
    var endOfTurn: EndOfTurnChoice {
        didSet {
            defaults.set(endOfTurn.rawValue, forKey: Key.endOfTurn)
            onChange?(.speechModel)
        }
    }

    var replyTimeoutSeconds: Double {
        didSet { defaults.set(replyTimeoutSeconds, forKey: Key.replyTimeoutSeconds) }
    }

    /// How long a reply stays on screen after it has been spoken; 0 means until dismissed.
    var autoDismissSeconds: Double {
        didSet { defaults.set(autoDismissSeconds, forKey: Key.autoDismissSeconds) }
    }

    /// Realtime calls use this quiet window after playback finishes; applied on the next call.
    var hangUpAfterQuietSeconds: Double {
        didSet { defaults.set(hangUpAfterQuietSeconds, forKey: Key.hangUpAfterQuietSeconds) }
    }

    var textSize: TextSizeChoice {
        didSet { defaults.set(textSize.rawValue, forKey: Key.textSize) }
    }

    var cardTheme: CardTheme {
        didSet { defaults.set(cardTheme.rawValue, forKey: Key.cardTheme) }
    }

    var pillPlacement: PillPlacement {
        didSet {
            defaults.set(pillPlacement.rawValue, forKey: Key.pillPlacement)
            onChange?(.placement)
        }
    }

    /// Empty until a home is chosen; the fleet context follows it.
    var firstmateHome: String {
        didSet {
            defaults.set(firstmateHome, forKey: Key.firstmateHome)
            onChange?(.assistant)
            onChange?(.autoSpeak)
        }
    }

    /// Empty means `<firstmateHome>/bin/fm-inbox.sh`.
    var inboxScript: String {
        didSet { defaults.set(inboxScript, forKey: Key.inboxScript) }
    }

    var resolvedInboxScript: String {
        inboxScript.isEmpty ? FirstmateHome.inboxScript(in: firstmateHome) : inboxScript
    }

    var firstmateHomeIsValid: Bool {
        FileManager.default.isExecutableFile(atPath: resolvedInboxScript)
    }

    /// Off sends every utterance straight to the first mate, as before the assistant existed.
    var assistantEnabled: Bool {
        didSet {
            defaults.set(assistantEnabled, forKey: Key.assistantEnabled)
            onChange?(.assistant)
        }
    }

    var voiceLane: VoiceLane {
        didSet {
            defaults.set(voiceLane.rawValue, forKey: Key.voiceLane)
            onChange?(.voiceLane)
        }
    }

    private(set) var realtimeEnabled: [String: Bool]

    /// Provider id to voice id; a lane without a saved choice uses its default (a male voice).
    private(set) var realtimeVoices: [String: String]

    func realtimeVoice(_ provider: RealtimeProvider) -> String {
        realtimeVoices[provider.id] ?? provider.defaultVoice
    }

    /// Takes effect on the next call: a realtime model cannot change voice once it has spoken.
    func setRealtimeVoice(_ voiceID: String, for provider: RealtimeProvider) {
        realtimeVoices[provider.id] = voiceID
        defaults.set(voiceID, forKey: Key.realtimeVoicePrefix + provider.id)
    }

    /// Off speaks only the opening sentence or two of a reply.
    var readWholeReply: Bool {
        didSet { defaults.set(readWholeReply, forKey: Key.readWholeReply) }
    }

    var outreachHangUpSeconds: Double {
        didSet { defaults.set(outreachHangUpSeconds, forKey: Key.outreachHangUpSeconds) }
    }

    var outreachVoice: OutreachVoice {
        didSet { defaults.set(outreachVoice.rawValue, forKey: Key.outreachVoice) }
    }

    var speakFirstmateReplies: Bool {
        didSet {
            defaults.set(speakFirstmateReplies, forKey: Key.speakFirstmateReplies)
            onChange?(.autoSpeak)
        }
    }

    /// Empty means the first `claude` found in the usual install locations.
    var claudePath: String {
        didSet {
            defaults.set(claudePath, forKey: Key.claudePath)
            onChange?(.assistant)
        }
    }

    var messengerModel: MessengerModel {
        didSet {
            defaults.set(messengerModel.rawValue, forKey: Key.messengerModel)
            onChange?(.assistant)
        }
    }

    var fleetActiveRefresh: FleetRefreshRate {
        didSet {
            defaults.set(fleetActiveRefresh.rawValue, forKey: Key.fleetActiveRefresh)
            onChange?(.fleetSchedule)
        }
    }

    var fleetIdleRefresh: FleetRefreshRate {
        didSet {
            defaults.set(fleetIdleRefresh.rawValue, forKey: Key.fleetIdleRefresh)
            onChange?(.fleetSchedule)
        }
    }

    var onboardingCompleted: Bool {
        didSet { defaults.set(onboardingCompleted, forKey: Key.onboardingCompleted) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Decided first: reading the speech model can write keys that would look like an old install.
        onboardingCompleted = Self.initialOnboardingCompleted(defaults)
        speechModel = Self.initialSpeechModel(defaults)
        voiceID = defaults.string(forKey: Key.voice) ?? VoiceChoice.defaultID
        speechSpeed = SpeechSpeed(rawValue: defaults.float(forKey: Key.speechSpeed)) ?? .brisk
        keepListeningAfterReply = defaults.object(forKey: Key.keepListeningAfterReply) == nil
            ? true : defaults.bool(forKey: Key.keepListeningAfterReply)
        hotkey = defaults.string(forKey: Key.hotkey).flatMap(HotkeyPreset.init) ?? .optionSpace
        silenceSeconds = Self.double(defaults, Key.silenceSeconds) ?? 0.8
        endOfTurn = defaults.string(forKey: Key.endOfTurn).flatMap(EndOfTurnChoice.init) ?? .silence
        replyTimeoutSeconds = Self.double(defaults, Key.replyTimeoutSeconds) ?? 60
        autoDismissSeconds = Self.double(defaults, Key.autoDismissSeconds) ?? 5
        let quiet = Self.double(defaults, Key.hangUpAfterQuietSeconds) ?? 10
        hangUpAfterQuietSeconds = SettingsOptions.hangUpAfterQuietSeconds.contains(quiet) ? quiet : 10
        textSize = defaults.string(forKey: Key.textSize).flatMap(TextSizeChoice.init) ?? .standard
        cardTheme = defaults.string(forKey: Key.cardTheme).flatMap(CardTheme.init) ?? .dark
        pillPlacement = defaults.string(forKey: Key.pillPlacement).flatMap(PillPlacement.init) ?? .notch
        firstmateHome = defaults.string(forKey: Key.firstmateHome) ?? FirstmateHome.defaultHome()
        inboxScript = defaults.string(forKey: Key.inboxScript) ?? ""
        assistantEnabled = defaults.object(forKey: Key.assistantEnabled) == nil
            ? true : defaults.bool(forKey: Key.assistantEnabled)
        readWholeReply = defaults.object(forKey: Key.readWholeReply) == nil
            ? true : defaults.bool(forKey: Key.readWholeReply)
        speakFirstmateReplies = defaults.object(forKey: Key.speakFirstmateReplies) == nil
            ? true : defaults.bool(forKey: Key.speakFirstmateReplies)
        outreachHangUpSeconds = Self.initialOutreachHangUp(defaults)
        outreachVoice = defaults.string(forKey: Key.outreachVoice).flatMap(OutreachVoice.init) ?? .kokoro
        let savedMessenger = defaults.string(forKey: Key.messengerModel).flatMap(MessengerModel.init) ?? .haiku
        messengerModel = MessengerModel.offered.contains(savedMessenger) ? savedMessenger : .haiku
        fleetActiveRefresh = defaults.string(forKey: Key.fleetActiveRefresh).flatMap(FleetRefreshRate.init) ?? .minute
        fleetIdleRefresh = defaults.string(forKey: Key.fleetIdleRefresh).flatMap(FleetRefreshRate.init) ?? .fourMinutes
        claudePath = defaults.string(forKey: Key.claudePath) ?? ""
        let savedLane = defaults.string(forKey: Key.voiceLane).flatMap(VoiceLane.init) ?? .onDevice
        voiceLane = savedLane
        // An existing realtime selection is the user's prior opt-in; never reset it on upgrade.
        realtimeEnabled = [RealtimeProvider.chatGPT, .grok].reduce(into: [:]) { enabled, provider in
            let key = Key.realtimeEnabledPrefix + provider.id
            enabled[provider.id] = defaults.object(forKey: key) == nil
                ? savedLane.provider == provider : defaults.bool(forKey: key)
        }
        realtimeVoices = Self.initialRealtimeVoices(defaults)
    }
}

extension AppSettings {
    /// An install that predates onboarding has settings saved already and is not asked again.
    static func initialOnboardingCompleted(_ defaults: UserDefaults) -> Bool {
        if defaults.object(forKey: Key.onboardingCompleted) != nil {
            return defaults.bool(forKey: Key.onboardingCompleted)
        }
        return Key.legacy.contains { defaults.object(forKey: $0) != nil }
    }

    /// Fluid Speech Pro replaces an earlier default or TDT v2 choice once, the first time it is
    /// found installed; any choice made after that sticks.
    private static func initialSpeechModel(_ defaults: UserDefaults) -> SpeechModelChoice {
        let stored = defaults.string(forKey: Key.speechModel).flatMap(SpeechModelChoice.init)
        guard FluidSpeechPro.isInstalled, !defaults.bool(forKey: Key.fluidSpeechProAdopted) else {
            return stored ?? .preferred
        }
        defaults.set(true, forKey: Key.fluidSpeechProAdopted)
        guard stored == nil || stored == .parakeetTdtV2 else { return stored ?? .preferred }
        defaults.set(SpeechModelChoice.fluidSpeechPro.rawValue, forKey: Key.speechModel)
        return .fluidSpeechPro
    }
}

extension AppSettings {
    func isRealtimeEnabled(_ provider: RealtimeProvider) -> Bool {
        realtimeEnabled[provider.id] ?? false
    }

    func setRealtimeEnabled(_ enabled: Bool, for provider: RealtimeProvider) {
        realtimeEnabled[provider.id] = enabled
        defaults.set(enabled, forKey: Key.realtimeEnabledPrefix + provider.id)
        if !enabled, voiceLane.provider == provider {
            voiceLane = .onDevice
        }
    }
}
