//  LiveCardTests.swift
//  NotchVoiceTests
//
//  Created by Michael Duong on 11/18/26.

@testable import NotchVoice
import Testing

/// Intent: the lock screen keeps the first mate's last spoken sentence after it stops (FLC-26).
struct LiveCardTests {
    private let reply = "Okay, I changed the voice. Curious how it sounds now."

    @Test func speakingShowsTheSentenceBeingSpoken() {
        let sentence = LiveCard.sentence(phase: .speaking, reply: reply, offset: 30, held: "")
        #expect(sentence == "Curious how it sounds now.")
    }

    @Test func afterSpeakingTheLastSentenceStays() {
        let held = "Curious how it sounds now."
        #expect(LiveCard.sentence(phase: .idle, reply: reply, offset: reply.utf16.count, held: held) == held)
        #expect(LiveCard.sentence(phase: .thinking, reply: "", offset: 0, held: held) == held)
    }

    @Test func blankMomentKeepsTheHeldSentence() {
        #expect(LiveCard.sentence(phase: .speaking, reply: "", offset: 0, held: "Hi.") == "Hi.")
    }
}

/// Intent: the island opens by itself once per spoken reply, never on screen or on a locked phone (FLC-47).
struct IslandAlertTests {
    private func alert(
        _ phase: LiveCard.Phase = .speaking,
        done: Bool = false,
        text: String = "Hi.",
        onScreen: Bool = false,
        unlocked: Bool = true
    ) -> Bool {
        LiveCard.shouldAlert(
            phase: phase, alreadyAlerted: done, sentence: text, appOnScreen: onScreen, unlocked: unlocked
        )
    }

    @Test func alertsOnceWhenVoiceStartsInBackground() {
        #expect(alert())
        #expect(!alert(done: true))
    }

    @Test func staysQuietOtherwise() {
        #expect(!alert(.thinking))
        #expect(!alert(text: ""))
        #expect(!alert(onScreen: true))
        #expect(!alert(unlocked: false))
    }
}

/// Intent: a first reply must not close the card. The Mac sends idle, waiting, listening, message or
/// reply before any sentence, and ending then makes the next card a request iOS refuses off screen (FLC-59).
struct LiveActivityLifetimeTests {
    @Test func macStatesBeforeSpeechKeepTheCard() {
        for state in ["idle", "waiting", "listening", "message", "reply", "thinking", "sending"] {
            let phase = LiveCard.phase(isTalking: false, isSpeaking: false, macState: state)
            #expect(!LiveCard.retiresActivity(phase: phase, spoken: ""))
        }
        #expect(!LiveCard.retiresActivity(phase: .idle, spoken: "Last line."))
        #expect(!LiveCard.retiresActivity(phase: .speaking, spoken: ""))
    }
}
