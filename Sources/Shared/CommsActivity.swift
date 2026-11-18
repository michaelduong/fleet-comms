//  CommsActivity.swift
//  FleetCommsPhone
//
//  Created by Michael Duong on 11/17/26.

import ActivityKit
import Foundation

/// The lock-screen Live Activity: the captain's words, then the sentence being spoken.
struct CommsActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable, Hashable { case listening, thinking, speaking, idle }
        var phase: Phase
        var words: String
        var sentence: String
    }

    var channel: String
}
