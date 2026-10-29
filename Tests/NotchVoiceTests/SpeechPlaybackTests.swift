//  SpeechPlaybackTests.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/29/26.

import Foundation
@testable import NotchVoice
import Testing

struct SpeechPlaybackTests {
    @Test func mapsSpokenWordsAcrossMarkdownAndUnspokenIntroductions() {
        let shown = "**Opening update.**\n\nRead [the report](https://example.com).\n\nFinal checks are ready."
        let spoken = "Firstmate replied. Opening update. Read the report. Final checks are ready."
        let offset = (spoken as NSString).range(of: "Final").location
        let playback = SpeechPlayback(id: UUID(), text: spoken, utf16Offset: offset)
        #expect(playback.displayOffset(in: shown) == (shown as NSString).range(of: "Final").location)
        let intro = SpeechPlayback(id: UUID(), text: spoken, utf16Offset: 0)
        #expect(intro.displayOffset(in: shown) == 0)
    }

    @Test func summaryDoesNotScrollThroughUnspokenDetails() {
        let shown = "The update is ready.\n\n" + String(
            repeating: "Additional details remain on screen.\n\n",
            count: 20
        )
        let spoken = "The update is ready. Details on screen."
        let playback = SpeechPlayback(id: UUID(), text: spoken, utf16Offset: spoken.utf16.count)
        #expect(playback.displayOffset(in: shown) < 25)
    }

    @Test func unicodeOffsetsAndMissingWordsStayWithinDisplayedText() {
        let shown = "🚀 Café is ready.\n\n最後の確認 is complete."
        let spoken = "Café is ready. 最後の確認 is complete."
        let offset = (spoken as NSString).range(of: "最後").location
        let playback = SpeechPlayback(id: UUID(), text: spoken, utf16Offset: offset)
        #expect(playback.displayOffset(in: shown) == (shown as NSString).range(of: "最後").location)
        #expect(SpeechPlayback(id: UUID(), text: "Unrelated words", utf16Offset: 100).displayOffset(in: shown) == 0)
    }

    @Test @MainActor func endedCallDropsPlaybackAndIgnoresLateProgress() throws {
        let name = "speech-lifetime-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: AppSettings.Key.fluidSpeechProAdopted)
        defaults.set("", forKey: AppSettings.Key.firstmateHome)
        let model = AppModel(settings: AppSettings(defaults: defaults))
        let call = RealtimeCall(
            provider: .grok, voice: "", source: .wav(URL(fileURLWithPath: "/unused")), silenceSeconds: 0.8
        ) { "" }
        model.call = call
        let playback = SpeechPlayback(id: UUID(), text: "An update is ready.", utf16Offset: 3)
        model.call(call, playback: playback)
        #expect(model.speechPlayback == playback)
        model.endCallQuietly()
        #expect(model.speechPlayback == nil)
        model.call(call, playback: playback)
        #expect(model.speechPlayback == nil)
        #expect(call.ended)
    }
}
