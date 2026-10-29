//  CardTheme.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation

enum CardTheme: String, CaseIterable, Identifiable {
    case dark
    case glass

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .dark: "Dark"
        case .glass: "Glass"
        }
    }
}
