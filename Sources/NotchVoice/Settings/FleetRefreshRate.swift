//  FleetRefreshRate.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation

enum FleetRefreshRate: String, CaseIterable, Identifiable {
    case thirtySeconds, minute, twoMinutes, fourMinutes, fiveMinutes, manual

    var id: String {
        rawValue
    }

    var seconds: Int? {
        switch self {
        case .thirtySeconds: 30
        case .minute: 60
        case .twoMinutes: 120
        case .fourMinutes: 240
        case .fiveMinutes: 300
        case .manual: nil
        }
    }

    var title: String {
        switch self {
        case .thirtySeconds: "30 seconds"
        case .minute: "1 minute"
        case .twoMinutes: "2 minutes"
        case .fourMinutes: "4 minutes"
        case .fiveMinutes: "5 minutes"
        case .manual: "Off — manual"
        }
    }

    var staleAfterSeconds: Int {
        max(300, 2 * (seconds ?? 0))
    }
}
