//  SettingsSection.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation
import Observation

enum SettingsSection: String, CaseIterable, Identifiable, Sendable {
    case general
    case voice
    case assistant
    case realtime
    case models
    case advanced
    case about

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .general: "General"
        case .voice: "Voice & Speech"
        case .assistant: "Assistant"
        case .realtime: "Realtime"
        case .models: "Models"
        case .advanced: "Advanced"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .voice: "waveform"
        case .assistant: "sparkles"
        case .realtime: "phone.badge.waveform"
        case .models: "shippingbox"
        case .advanced: "wrench.and.screwdriver"
        case .about: "info.circle"
        }
    }
}

/// The section the Settings window shows; shared so other windows can open a section.
@MainActor
@Observable
final class SettingsNavigation {
    var section: SettingsSection = .general
}

/// Everything the Settings sections read or drive.
@MainActor
struct SettingsDependencies {
    let settings: AppSettings
    let model: AppModel
    let library: ModelLibrary
    let launchAtLogin: LaunchAtLogin
    let developer: DeveloperActions
    let showOnboarding: () -> Void
}
