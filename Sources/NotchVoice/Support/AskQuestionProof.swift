//  AskQuestionProof.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/29/26.

#if DEBUG
    import AppKit

    /// `--question-proof <folder>`: the real pill and question bridge against a scratch home, writing a
    /// PNG of the pill after every change; proof runs load no speech models.
    @MainActor
    enum AskQuestionProof {
        private static var pill: NotchPanelController?

        static func startIfRequested(model: AppModel, settingsWindow: SettingsWindowController) -> Bool {
            guard let path = DeveloperActions.argument("--question-proof") else { return false }
            guard Bundle.main.bundleIdentifier?.hasPrefix("com.fleetcomms.proof.") == true,
                  !model.settings.firstmateHome.isEmpty else {
                NSApp.terminate(nil)
                return true
            }
            let folder = URL(fileURLWithPath: path)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let menu = StatusMenuBuilder(settings: model.settings, model: model, settingsWindow: settingsWindow)
            let controller = NotchPanelController(model: model, menu: menu)
            controller.show()
            pill = controller
            model.startQuestions()
            Task { await capture(model: model, pill: controller, to: folder) }
            if let script = DeveloperActions.argument("--question-proof-script") {
                Task { await run(script: URL(fileURLWithPath: script), model: model, pill: controller) }
            }
            return true
        }

        private static func capture(model: AppModel, pill: NotchPanelController, to folder: URL) async {
            var last = ""
            var frame = 0
            while !Task.isCancelled {
                let store = model.questions
                let key = "\(model.displayState)-\(store.current?.id ?? "")-\(store.requests.count)-\(store.page)"
                    + "-\(store.draft.selected.sorted())-\(store.draft.text)-\(store.sending)"
                    + "-\(store.confirmation ?? "")-\(model.transcript)-\(model.settings.pillPlacement)"
                    + "-\(Int(pill.contentFrameOnScreen.height))"
                if key != last {
                    last = key
                    try? await Task.sleep(for: .milliseconds(400))
                    if model.displayState == .question {
                        write(pill, frame: frame, to: folder)
                        frame += 1
                    }
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }

        /// The pill's PNG plus its screen rectangle (top-left origin), so a proof script can click it.
        private static func write(_ pill: NotchPanelController, frame: Int, to folder: URL) {
            let content = pill.contentFrameOnScreen
            UICapture.write(pill.window, within: content, to: folder.appendingPathComponent("card-\(frame).png"))
            let top = NSScreen.screens[0].frame.maxY - content.maxY
            let rect = "\(Int(content.minX)),\(Int(top)),\(Int(content.width)),\(Int(content.height))"
            try? rect.write(to: folder.appendingPathComponent("card-\(frame).txt"), atomically: true, encoding: .utf8)
        }
    }
#endif
