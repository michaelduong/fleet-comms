//  AppSettings+Keys.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

extension AppSettings {
    enum Key {
        static let speechModel = "speechModel"
        static let voice = "voice"
        static let speechSpeed = "speechSpeed"
        static let keepListeningAfterReply = "keepListeningAfterReply"
        static let hotkey = "hotkey"
        static let silenceSeconds = "silenceSeconds"
        static let endOfTurn = "endOfTurn"
        static let replyTimeoutSeconds = "replyTimeoutSeconds"
        static let textSize = "textSize"
        static let cardTheme = "cardTheme"
        static let pillPlacement = "pillPlacement"
        static let firstmateHome = "firstmateHome"
        static let inboxScript = "inboxScript"
        static let assistantEnabled = "assistantEnabled"
        static let readWholeReply = "readWholeReply"
        static let speakFirstmateReplies = "speakFirstmateReplies"
        static let outreachHangUpSeconds = "outreachHangUpSeconds"
        static let outreachVoice = "outreachVoice"
        static let claudePath = "claudePath"
        static let messengerModel = "messengerModel"
        static let fleetActiveRefresh = "fleetActiveRefresh"
        static let fleetIdleRefresh = "fleetIdleRefresh"
        static let fluidSpeechProAdopted = "fluidSpeechProAdopted"
        static let autoDismissSeconds = "autoDismissSeconds"
        static let hangUpAfterQuietSeconds = "hangUpAfterQuietSeconds"
        static let voiceLane = "voiceLane"
        static let onboardingCompleted = "onboardingCompleted"
        static let realtimeVoicePrefix = "realtimeVoice."
        static let realtimeEnabledPrefix = "realtimeEnabled."

        /// Any of these in the defaults means the app has run before this version.
        static let legacy = [
            speechModel, voice, speechSpeed, keepListeningAfterReply, hotkey, silenceSeconds, endOfTurn,
            replyTimeoutSeconds, textSize, firstmateHome, inboxScript, assistantEnabled, readWholeReply,
            claudePath, fluidSpeechProAdopted, autoDismissSeconds, hangUpAfterQuietSeconds, voiceLane
        ]
    }
}
