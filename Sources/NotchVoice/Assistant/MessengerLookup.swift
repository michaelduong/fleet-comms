//  MessengerLookup.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation

/// App-side retrieval is identical for every model; no CLI gets a filesystem or shell tool.
struct MessengerLookup: Sendable {
    let dataDirectory: URL

    private struct Match {
        let record: LookupFiles.Record
        let score: Int
    }

    func context(for input: AssistantTurnInput) -> String? {
        let words = Set(input.ownerSaid.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted))
        let cues: Set = [
            "where", "what", "when", "why", "how", "do", "did", "does", "have", "had", "still",
            "remember", "find", "search", "lookup", "look", "locate", "prior", "previous",
            "plan", "plans", "report", "reports", "screenshots", "decisions", "backlog"
        ]
        guard input.ownerSaid.contains("?") || !words.isDisjoint(with: cues) else { return nil }
        var question = input.ownerSaid
        if Self.terms(question).count < 2, let previous = input.recent.last {
            question += " " + previous.owner
        }
        return search(question)
    }

    func search(_ question: String) -> String {
        let terms = Self.terms(question)
        guard !terms.isEmpty else { return "No searchable topic in this turn." }
        var files = LookupFiles(terms: terms)
        let matches = files.read(dataDirectory: dataDirectory).compactMap { record -> Match? in
            let path = record.path.replacingOccurrences(of: dataDirectory.path, with: "").lowercased()
            let text = record.text?.lowercased() ?? ""
            let found = terms.filter { path.contains($0) || text.contains($0) }.count
            guard found == terms.count else { return nil }
            let pathHits = terms.filter { path.contains($0) }.count
            let reportBonus = path.hasSuffix("/report.md") ? 3 : 0
            return Match(record: record, score: found * 10 + pathHits * 8 + reportBonus)
        }.sorted {
            $0.score == $1.score ? $0.record.path < $1.record.path : $0.score > $1.score
        }
        let documents = matches.filter { $0.record.text != nil }.prefix(4)
        let images = matches.filter { $0.record.text == nil }.prefix(6)
        let results = documents.map { match in
            "File: \(match.record.path)\n" + Self.excerpt(match.record.text ?? "", terms: terms)
        } + images.map { "Image path (contents not inspected): \($0.record.path)" }
        return results.isEmpty
            ? "No matching records found in the bounded data search. This does not prove they were deleted."
            : "File and Image path entries were verified on disk this turn. Their text is historical, " +
            "not live fleet status. Search is bounded and may be incomplete.\n" +
            results.joined(separator: "\n\n")
    }

    private static func excerpt(_ text: String, terms: Set<String>) -> String {
        let lines = text.components(separatedBy: .newlines)
        let ranked = lines.indices.sorted { left, right in
            let leftHits = terms.filter { lines[left].lowercased().contains($0) }.count
            let rightHits = terms.filter { lines[right].lowercased().contains($0) }.count
            return leftHits == rightHits ? left < right : leftHits > rightHits
        }
        var selected: Set = [0]
        for index in ranked.prefix(4) {
            selected.formUnion(max(0, index - 1) ... min(lines.count - 1, index + 2))
        }
        return String(selected.sorted().map { "\($0 + 1): \(lines[$0])" }.joined(separator: "\n").prefix(2400))
    }

    private static func terms(_ question: String) -> Set<String> {
        let stop: Set = [
            "the", "and", "for", "are", "was", "were", "did", "does", "that", "this", "those", "these",
            "have", "has", "had", "still", "our", "you", "your", "can", "could", "would", "should",
            "what", "where", "when", "which", "how", "about", "with", "from", "there", "they", "them",
            "please", "look", "find", "show", "tell", "remember", "decide", "decided", "decision",
            "plan", "plans", "report", "reports", "screenshot", "screenshots", "folder", "files", "old"
        ]
        return Set(question.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !stop.contains($0) }.prefix(12))
    }
}
