//  FleetSummary.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation

/// Trims `fm-bearings-snapshot.sh --json` (schema fm-bearings.v1) to a few compact lines the
/// assistant can answer fleet questions from. Links and paths are dropped.
enum FleetSummary {
    static let rowsPerSection = 10
    static let maxLineLength = 160

    static func make(from json: Data) throws -> String {
        let bearings = try JSONDecoder().decode(FleetBearings.self, from: json)
        var lines = ["Snapshot generated \(bearings.generated ?? "at an unknown time")."]
        lines += section("Underway", bearings.inFlight) { row in
            [row.name ?? row.id, row.state.map { "(\($0))" }, row.doing.map { "- \($0)" }]
        }
        lines += section("Other homes", bearings.secondmates) { row in
            [row.id, row.state.map { "(\($0))" }, row.doing.map { "- \($0)" }]
        }
        lines += section("Waiting on the owner's decision", bearings.decisionsOpen) { row in
            [row.summary ?? row.id]
        }
        lines += section("Queued next", bearings.gates) { row in
            [row.title ?? row.id, row.reason.flatMap { $0 == "-" ? nil : "- \($0)" }]
        }
        lines += section("Recently landed", bearings.landed) { row in
            [row.what ?? row.id, row.owner.map { "(\($0))" }]
        }
        return lines.joined(separator: "\n")
    }

    private static func section(_ title: String, _ rows: [FleetRow]?, fields: (FleetRow) -> [String?]) -> [String] {
        let rows = rows ?? []
        guard !rows.isEmpty else { return ["\(title): none."] }
        let shown = rows.prefix(rowsPerSection).map { row in
            "- " + clean(fields(row).compactMap(\.self).joined(separator: " "))
        }
        let more = rows.count > rowsPerSection ? ["- and \(rows.count - rowsPerSection) more"] : []
        return ["\(title) (\(rows.count)):"] + shown + more
    }

    private static func clean(_ text: String) -> String {
        let stripped = text
            .replacingOccurrences(of: #"\b(https?://|www\.)\S+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(^|\s)(/|~/)\S+"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard stripped.count > maxLineLength else { return stripped }
        return String(stripped.prefix(maxLineLength - 1)) + "…"
    }
}

/// The slice of fm-bearings.v1 the summary reads.
private struct FleetBearings: Decodable {
    let generated: String?
    let inFlight: [FleetRow]?
    let secondmates: [FleetRow]?
    let decisionsOpen: [FleetRow]?
    let gates: [FleetRow]?
    let landed: [FleetRow]?

    enum CodingKeys: String, CodingKey {
        case generated, secondmates, gates, landed
        case inFlight = "in_flight"
        case decisionsOpen = "decisions_open"
    }
}

private struct FleetRow: Decodable {
    let id: String?
    let name: String?
    let title: String?
    let what: String?
    let summary: String?
    let state: String?
    let doing: String?
    let reason: String?
    let owner: String?
}
