//  AskQuestionStore.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/29/26.

import Foundation
import Observation

@MainActor
@Observable
final class AskQuestionStore {
    private(set) var requests: [AskRequest] = []
    private(set) var drafts: [AskDraft] = []
    private(set) var page = 0
    private(set) var sending = false
    private(set) var confirmation: String?
    private(set) var error: String?
    @ObservationIgnored var onRequestEnded: (() -> Void)?
    @ObservationIgnored private var root: URL?
    @ObservationIgnored private var polling: Task<Void, Never>?
    @ObservationIgnored private var confirmationTask: Task<Void, Never>?

    var current: AskRequest? {
        requests.first
    }

    var isShowing: Bool {
        current != nil || confirmation != nil
    }

    var question: AskQuestion? {
        current?.questions[page]
    }

    var draft: AskDraft {
        drafts.indices.contains(page) ? drafts[page] : AskDraft()
    }

    var canSend: Bool {
        guard let current, drafts.count == current.questions.count else { return false }
        return !sending && zip(drafts, current.questions).allSatisfy { !$0.answer(for: $1).isEmpty }
    }

    func start(home: String) {
        stop()
        guard !home.isEmpty else { return }
        let folder = URL(fileURLWithPath: (home as NSString).expandingTildeInPath)
            .appendingPathComponent("state/fleet-comms-questions", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
            )
            root = folder
        } catch { return }
        polling = Task { [weak self] in
            while !Task.isCancelled {
                self?.poll()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    func stop() {
        polling?.cancel()
        polling = nil
        if let root {
            try? FileManager.default.removeItem(at: root.appendingPathComponent("heartbeat.json"))
        }
        root = nil
        requests = []
        resetDrafts()
    }

    func poll() {
        guard let root else { return }
        try? write(["time": Date().timeIntervalSince1970], name: "heartbeat.json", folder: root)
        let previous = current
        if let current, sending, let folder = folder(for: current),
           FileManager.default.fileExists(atPath: folder.appendingPathComponent("consumed.json").path) {
            try? write(["received": true], name: "ack.json", folder: folder)
            confirm(current.agent)
        }
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        )) ?? []
        let pending = folders.compactMap { folder -> AskRequest? in
            guard UUID(uuidString: folder.lastPathComponent) != nil,
                  let data = try? Data(contentsOf: folder.appendingPathComponent("request.json")),
                  data.count <= 256 * 1024,
                  let request = try? JSONDecoder().decode(AskRequest.self, from: data),
                  request.id == folder.lastPathComponent, request.isValid,
                  request.expiresAt > Date().timeIntervalSince1970,
                  !FileManager.default.fileExists(atPath: folder.appendingPathComponent("dismiss.json").path),
                  !FileManager.default.fileExists(atPath: folder.appendingPathComponent("consumed.json").path)
            else { return nil }
            return request
        }.sorted { $0.expiresAt < $1.expiresAt }
        // Keep the question being answered in front when another session asks at the same time.
        let active = previous.flatMap { prior in pending.first { $0.id == prior.id } }
        let ordered = active.map { [$0] + pending.filter { $0.id != active?.id } } ?? pending
        // The pill observes this store every tick; an unchanged list must not redraw it.
        if ordered != requests {
            requests = ordered
        }
        if previous?.id != current?.id {
            onRequestEnded?()
            resetDrafts()
        }
    }

    func select(_ index: Int) {
        guard !sending, let question, question.options.indices.contains(index) else { return }
        drafts[page].toggle(index, question: question)
    }

    func type(_ text: String) {
        guard !sending, let question else { return }
        drafts[page].type(text, question: question)
    }

    func go(to index: Int) {
        guard !sending, let current, current.questions.indices.contains(index) else { return }
        onRequestEnded?()
        page = index
    }

    func send() {
        guard canSend, let current, let folder = folder(for: current),
              current.expiresAt > Date().timeIntervalSince1970 else { return }
        do {
            let answers = Dictionary(uniqueKeysWithValues: zip(current.questions, drafts).map {
                ($0.question, $1.answer(for: $0))
            })
            try write(answers, name: "answer.json", folder: folder)
            sending = true
            error = nil
            onRequestEnded?()
        } catch {
            self.error = "Could not deliver. Try again or answer in the terminal."
        }
    }

    func dismiss() {
        guard let current, let folder = folder(for: current) else { return }
        try? write(["dismissed": true], name: "dismiss.json", folder: folder)
        poll()
    }

    private func confirm(_ agent: String) {
        confirmation = "Sent to \(agent)"
        confirmationTask?.cancel()
        confirmationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.confirmation = nil
        }
    }

    private func resetDrafts() {
        drafts = current?.questions.map { _ in AskDraft() } ?? []
        page = 0
        sending = false
        error = nil
    }

    private func folder(for request: AskRequest) -> URL? {
        root?.appendingPathComponent(request.id, isDirectory: true)
    }

    private func write(_ value: some Encodable, name: String, folder: URL) throws {
        let data = try JSONEncoder().encode(value)
        try data.write(to: folder.appendingPathComponent(name), options: [.atomic])
    }
}
