//  AskQuestionTests.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/29/26.

import Foundation
@testable import NotchVoice
import Testing

@MainActor
struct AskQuestionTests {
    @Test func answersPreserveLabelsAndMultiSelectOrder() {
        let single = question(multi: false)
        var draft = AskDraft()
        #expect(draft.answer(for: single).isEmpty)
        #expect(single.options[0].title == "Swift")
        #expect(single.options[0].recommended)
        draft.toggle(0, question: single)
        #expect(draft.answer(for: single) == "Swift (Recommended)")
        draft.type("A typed answer", question: single)
        #expect(draft.selected.isEmpty)
        #expect(draft.answer(for: single) == "A typed answer")
        draft.toggle(1, question: single)
        #expect(draft.text.isEmpty)
        #expect(draft.answer(for: single) == "Python")

        let multi = question(multi: true)
        draft.toggle(0, question: multi)
        draft.type("Another choice", question: multi)
        #expect(draft.answer(for: multi) == "Swift (Recommended), Python, Another choice")
        draft.toggle(1, question: multi)
        #expect(draft.answer(for: multi) == "Swift (Recommended), Another choice")
    }

    @Test func queuesRequestsSendsAllPagesAndWaitsForHookAcknowledgment() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let store = AskQuestionStore()
        store.start(home: home.path)
        defer { store.stop() }
        let root = home.appendingPathComponent("state/fleet-comms-questions")
        let first = request(questions: [question(multi: false), question(multi: true, text: "Which checks?")])
        let folder = try save(first, to: root)
        store.poll()
        #expect(store.current == first)
        store.select(0)
        #expect(!store.canSend)
        store.go(to: 1)
        store.select(1)
        store.type("UI proof")
        #expect(store.canSend)
        store.go(to: 0)
        #expect(store.draft.selected == [0])

        let second = request(questions: [question(multi: false)], expires: Date().timeIntervalSince1970 + 10)
        let secondFolder = try save(second, to: root)
        store.poll()
        #expect(store.current == first)
        #expect(store.requests.count == 2)
        store.send()
        #expect(store.sending)
        #expect(store.confirmation == nil)
        let answers = try JSONDecoder().decode(
            [String: String].self, from: Data(contentsOf: folder.appendingPathComponent("answer.json"))
        )
        #expect(answers["Which language?"] == "Swift (Recommended)")
        #expect(answers["Which checks?"] == "Python, UI proof")
        try Data("{}".utf8).write(to: folder.appendingPathComponent("consumed.json"))
        store.poll()
        #expect(store.confirmation == "Sent to claude-test")
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("ack.json").path))
        #expect(store.current == second)
        store.dismiss()
        #expect(store.current == nil)
        #expect(FileManager.default.fileExists(atPath: secondFolder.appendingPathComponent("dismiss.json").path))
    }

    @Test func expiredOrRemovedRequestsDismissWithoutSendingAndResetDictation() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let store = AskQuestionStore()
        store.start(home: home.path)
        defer { store.stop() }
        let root = home.appendingPathComponent("state/fleet-comms-questions")
        let expired = request(questions: [question(multi: false)], expires: 1)
        _ = try save(expired, to: root)
        store.poll()
        #expect(store.requests.isEmpty)
        let active = request(questions: [question(multi: false)])
        let folder = try save(active, to: root)
        store.poll()
        var ended = false
        store.onRequestEnded = { ended = true }
        store.type("Typed")
        try FileManager.default.removeItem(at: folder)
        store.poll()
        #expect(ended)
        #expect(store.current == nil)
        #expect(!store.canSend)
        #expect(store.draft.text.isEmpty)
        #expect(store.confirmation == nil)
    }

    @Test func pendingQuestionFillsTheIdlePillAndYieldsToOtherStates() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let name = "NotchVoice.ask-display.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults)
        settings.assistantEnabled = false
        settings.firstmateHome = home.path
        let model = AppModel(settings: settings)
        model.startQuestions()
        defer { model.stopQuestions() }
        #expect(model.displayState == .idle)
        let root = home.appendingPathComponent("state/fleet-comms-questions")
        let folder = try save(request(questions: [question(multi: false)]), to: root)
        model.questions.poll()
        #expect(model.displayState == .question)
        #expect(model.questionTakesKeyboard)

        let reply = NotchState.reply(text: "Done", speaking: false, from: .firstMate)
        model.state = reply
        #expect(model.displayState == reply)
        model.state = .listening
        #expect(model.displayState == .listening)
        model.questionDictation = { _ in }
        #expect(model.displayState == .question)
        model.questionDictation = nil
        model.state = .idle
        #expect(model.displayState == .question)

        try FileManager.default.removeItem(at: folder)
        model.questions.poll()
        #expect(model.displayState == .idle)
        #expect(!model.questionTakesKeyboard)
    }

    private func question(multi: Bool, text: String = "Which language?") -> AskQuestion {
        AskQuestion(question: text, header: "Language", options: [
            .init(label: "Swift (Recommended)", description: "Native UI"),
            .init(label: "Python", description: "Scripting")
        ], multiSelect: multi)
    }

    private func request(questions: [AskQuestion], expires: Double = Date().timeIntervalSince1970 + 120) -> AskRequest {
        AskRequest(
            id: UUID().uuidString, agent: "claude-test", sessionID: "scratch", toolUseID: UUID().uuidString,
            expiresAt: expires, questions: questions
        )
    }

    private func save(_ request: AskRequest, to root: URL) throws -> URL {
        let folder = root.appendingPathComponent(request.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(request).write(to: folder.appendingPathComponent("request.json"))
        return folder
    }
}
