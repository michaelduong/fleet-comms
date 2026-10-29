//  FleetSummaryTests.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation
@testable import NotchVoice
import Testing

struct FleetSummaryTests {
    @Test func summarisesSectionsWithoutLinksOrPaths() throws {
        let json = """
        {"schema":"fm-bearings.v1","generated":"2026-10-28T01:10:39Z",
         "in_flight":[{"id":"t1","name":"Notch Voice fast lane","state":"working","doing":"see /Users/x/log.txt now"}],
         "secondmates":[],
         "decisions_open":[{"id":"d1","summary":"Pick a model"}],
         "gates":[{"id":"g1","title":"SeatMap follow-ups","reason":"-"}],
         "landed":[{"id":"l1","what":"Merged https://github.com/o/r/pull/1 fix","owner":"(main)"}]}
        """
        let summary = try FleetSummary.make(from: Data(json.utf8))
        #expect(summary.contains("Underway (1):\n- Notch Voice fast lane (working) - see now"))
        #expect(summary.contains("Other homes: none."))
        #expect(summary.contains("Waiting on the owner's decision (1):\n- Pick a model"))
        #expect(summary.contains("Queued next (1):\n- SeatMap follow-ups\n"))
        #expect(summary.contains("- Merged fix ((main))"))
        #expect(!summary.contains("http"))
        #expect(!summary.contains("/Users"))
    }

    @Test func longSectionsAreBounded() throws {
        let rows = (1 ... 14).map { #"{"id":"g\#($0)","title":"Gate \#($0)"}"# }.joined(separator: ",")
        let summary = try FleetSummary.make(from: Data(#"{"gates":[\#(rows)]}"#.utf8))
        #expect(summary.contains("Queued next (14):"))
        #expect(summary.contains("- Gate 10\n- and 4 more"))
        #expect(!summary.contains("Gate 11"))
    }
}
