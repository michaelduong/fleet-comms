//  AskQuestionProof+Script.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/29/26.

#if DEBUG
    import AppKit

    extension AskQuestionProof {
        /// `--question-proof-script <file>`: one action per line, a moment apart, so a proof needs no
        /// pointer: wait, select N, go N, type TEXT, send, consume, dismiss, dictate TEXT, placement NAME,
        /// reply TEXT (a silent reply with its dismissal delay), dismissReply, sleep SECONDS, quit.
        static func run(script: URL, model: AppModel, pill: NotchPanelController) async {
            let lines = (try? String(contentsOf: script, encoding: .utf8))?.split(separator: "\n") ?? []
            for line in lines {
                let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
                guard let command = parts.first else { continue }
                await perform(command, parts.count > 1 ? parts[1] : "", model: model, pill: pill)
                try? await Task.sleep(for: .seconds(1.2))
            }
        }

        private static func perform(
            _ command: String, _ argument: String, model: AppModel, pill: NotchPanelController
        ) async {
            switch command {
            case "wait":
                while model.questions.current == nil {
                    try? await Task.sleep(for: .milliseconds(200))
                }
            case "dictate": await dictate(argument, model: model)
            case "placement":
                model.settings.pillPlacement = PillPlacement(rawValue: argument) ?? .notch
                pill.placementChanged()
            case "quit": NSApp.terminate(nil)
            case "reply", "dismissReply", "sleep": await replyStep(command, argument, model: model)
            default: act(command, argument, on: model.questions, home: model.settings.firstmateHome)
            }
        }

        /// The reply window without speech: a reply already spoken, then its own dismissal delay.
        private static func replyStep(_ command: String, _ argument: String, model: AppModel) async {
            switch command {
            case "reply":
                model.state = .reply(text: argument, speaking: false, from: .firstMate)
                model.scheduleAutoDismiss()
            case "dismissReply": model.dismiss()
            default: try? await Task.sleep(for: .seconds(Double(argument) ?? 1))
            }
        }

        private static func act(_ command: String, _ argument: String, on store: AskQuestionStore, home: String) {
            switch command {
            case "select": store.select(Int(argument) ?? 0)
            case "go": store.go(to: Int(argument) ?? 0)
            case "type": store.type(argument)
            case "send": store.send()
            case "consume": consume(store, home: home)
            case "dismiss": store.dismiss()
            default: break
            }
        }

        /// What the hook does once it has read the answer.
        private static func consume(_ store: AskQuestionStore, home: String) {
            guard let id = store.current?.id else { return }
            let folder = URL(fileURLWithPath: home).appendingPathComponent("state/fleet-comms-questions/\(id)")
            try? Data("{}".utf8).write(to: folder.appendingPathComponent("consumed.json"))
        }

        /// Shows the dictation row as a live transcript would, then delivers the text as a finished dictation.
        private static func dictate(_ transcript: String, model: AppModel) async {
            model.state = .listening
            model.questionDictation = { _ in }
            model.level = 0.6
            model.transcript = transcript
            try? await Task.sleep(for: .seconds(2))
            model.questionDictation = nil
            model.state = .idle
            model.questions.type(transcript)
        }
    }
#endif
