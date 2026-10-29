//  SpokenSummaryTests.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

@testable import NotchVoice
import Testing

struct SpokenSummaryTests {
    @Test func shortReplyIsSpokenWhole() {
        #expect(SpokenSummary.make(from: "Done. The build is green.") == "Done. The build is green.")
    }

    @Test func longReplyKeepsTwoSentencesAndPointsToScreen() {
        let reply = "Merged the fix. CI passed on the first run. Three follow-ups remain. I filed them."
        #expect(SpokenSummary.make(from: reply) == "Merged the fix. CI passed on the first run. Details on screen.")
    }

    @Test func linksAndCodeAreNotSpoken() {
        let reply = """
        Opened the PR at https://github.com/example/repo/pull/12 for review.

        ```swift
        let x = 1
        ```
        """
        #expect(SpokenSummary.make(from: reply) == "Opened the PR at for review. Details on screen.")
    }

    @Test func markdownLinkKeepsItsText() {
        #expect(SpokenSummary.make(from: "See [the plan](https://x.y/z).") == "See the plan. Details on screen.")
    }

    @Test func markdownSyntaxIsStripped() {
        let reply = "## Status\n\n- **Build** is `green`\n- Tests pass"
        #expect(SpokenSummary.make(from: reply) == "Status. Build is. Details on screen.")
    }

    @Test func overlongSentenceIsTruncated() {
        let reply = String(repeating: "word ", count: 80) + "end."
        let spoken = SpokenSummary.make(from: reply)
        #expect(spoken.hasSuffix("… Details on screen."))
        #expect(spoken.count < SpokenSummary.maxSpokenLength + 30)
    }

    @Test func wholeReplyKeepsEverySentence() {
        let reply = "Merged the fix. CI passed on the first run. See https://x.y/z for logs. Three follow-ups remain."
        #expect(
            SpokenSummary.whole(from: reply)
                == "Merged the fix. CI passed on the first run. See for logs. Three follow-ups remain."
        )
    }

    @Test func wholeReplySettingPreservesLongParagraphsWhileOffKeepsTheSummary() {
        let opening = "The detailed update is ready. The isolated build passed."
        let longSentence = String(repeating: "Every detail stays in the spoken reply, ", count: 10)
            + "including the end."
        let reply = opening + "\n\n" + longSentence + "\n\nThe final verification phrase is silver meadow lantern."
        let whole = SpokenSummary.make(from: reply, readWholeReply: true)
        #expect(whole == reply.replacingOccurrences(of: "\n\n", with: " "))
        #expect(ReplySpeaker.parts(of: whole).last == "The final verification phrase is silver meadow lantern.")
        #expect(SpokenSummary.make(from: reply, readWholeReply: false) == opening + " Details on screen.")
    }

    @Test func wholeReplyOfOnlyCodePointsToScreen() {
        #expect(SpokenSummary.whole(from: "```\nlet x = 1\n```") == SpokenSummary.detailsSuffix)
    }

    @Test func speechIsQueuedSentenceBySentence() {
        #expect(ReplySpeaker.parts(of: "One. Two! Three?") == ["One.", "Two!", "Three?"])
        #expect(ReplySpeaker.parts(of: "No end punctuation") == ["No end punctuation"])
    }

    @Test func decimalsDoNotSplitSentences() {
        #expect(SpokenSummary.make(from: "Version 1.5 shipped today.") == "Version 1.5 shipped today.")
    }
}
