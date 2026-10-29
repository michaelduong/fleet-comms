//  AskQuestion.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/29/26.

import Foundation

struct AskRequest: Codable, Identifiable, Equatable {
    let id: String
    let agent: String
    let sessionID: String
    let toolUseID: String
    let expiresAt: Double
    let questions: [AskQuestion]

    var isValid: Bool {
        UUID(uuidString: id) != nil && (1 ... 4).contains(questions.count)
            && Set(questions.map(\.question)).count == questions.count
            && questions.allSatisfy { !$0.question.isEmpty && (2 ... 4).contains($0.options.count) }
    }
}

struct AskQuestion: Codable, Equatable {
    struct Option: Codable, Equatable {
        let label: String
        let description: String?

        var recommended: Bool {
            label.hasSuffix("(Recommended)")
        }

        var title: String {
            recommended ? String(label.dropLast("(Recommended)".count)).trimmingCharacters(in: .whitespaces) : label
        }
    }

    let question: String
    let header: String
    let options: [Option]
    let multiSelect: Bool?
}

struct AskDraft {
    var selected: Set<Int> = []
    var text = ""

    func answer(for question: AskQuestion) -> String {
        let labels = selected.sorted().compactMap { index in
            question.options.indices.contains(index) ? question.options[index].label : nil
        }
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return (labels + (typed.isEmpty ? [] : [typed])).joined(separator: ", ")
    }

    mutating func toggle(_ index: Int, question: AskQuestion) {
        if selected.contains(index) {
            selected.remove(index)
        } else if question.multiSelect == true {
            selected.insert(index)
        } else {
            selected = [index]
            text = ""
        }
    }

    mutating func type(_ value: String, question: AskQuestion) {
        text = value
        if question.multiSelect != true, !value.isEmpty {
            selected = []
        }
    }
}
