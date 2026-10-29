//  AppModel+Questions.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/29/26.

import Foundation

extension AppModel {
    /// What the pill shows. A waiting Claude question fills the idle pill and stays while a reply is
    /// dictated for it; anything else the pill is doing comes first until it is over.
    var displayState: NotchState {
        switch state {
        case .idle where questions.isShowing, .listening where questionDictation != nil: .question
        default: state
        }
    }

    /// The pill may take keystrokes only while a question's controls are on screen.
    var questionTakesKeyboard: Bool {
        displayState == .question && questions.current != nil && !questions.sending
    }

    /// Watches the selected firstmate home for Claude questions; the pill shows them while it is idle.
    func startQuestions() {
        questions.onRequestEnded = { [weak self] in self?.stopQuestionDictation() }
        questions.start(home: settings.firstmateHome)
    }

    func stopQuestions() {
        stopQuestionDictation()
        questions.stop()
    }

    func toggleQuestionDictation() {
        if questionDictation != nil {
            stopQuestionDictation()
        } else {
            beginQuestionDictation { [weak self] text in self?.questions.type(text) }
        }
    }

    /// Dictates a question reply through the local recognizer; the text never becomes a note or a call.
    func beginQuestionDictation(
        feed: any AudioFeed = MicrophoneFeed(), onText: @escaping @MainActor @Sendable (String) -> Void
    ) {
        guard modelsReady else {
            show(message: "Voice models are still loading. You can type your answer.", autoHideAfter: 3)
            return
        }
        if !(feed is WavFileFeed) {
            let retry: @MainActor @Sendable () -> Void = { [weak self] in
                self?.beginQuestionDictation(feed: MicrophoneFeed(), onText: onText)
            }
            guard microphoneAllowed(retry: retry) else { return }
        }
        startListening(feed: feed, notePrefix: "")
        if state == .listening {
            questionDictation = onText
        }
    }

    func stopQuestionDictation() {
        guard questionDictation != nil else { return }
        cancelListeningSession()
        state = .idle
    }
}
