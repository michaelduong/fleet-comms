//  CommsActivity.swift
//  FleetCommsPhone
//
//  Created by Michael Duong on 11/17/26.

import ActivityKit
import Foundation

/// The lock-screen Live Activity: the first mate's sentence, or Listening / Thinking while it is not speaking.
struct CommsActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        typealias Phase = LiveCard.Phase
        var phase: Phase
        var sentence: String
        /// Which of the three dots are lit while Listening or Thinking.
        var dots: Int = 3
    }

    var channel: String
}
