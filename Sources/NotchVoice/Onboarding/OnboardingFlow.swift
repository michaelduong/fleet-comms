//  OnboardingFlow.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation
import Observation

enum OnboardingStep: Int, CaseIterable, Identifiable, Sendable {
    case welcome
    case microphone
    case firstMate
    case models
    case done

    var id: Int {
        rawValue
    }

    var title: String {
        switch self {
        case .welcome: "Welcome"
        case .microphone: "Microphone"
        case .firstMate: "Firstmate"
        case .models: "Models"
        case .done: "Ready"
        }
    }

    var symbol: String {
        switch self {
        case .welcome: "hand.wave"
        case .microphone: "mic"
        case .firstMate: "person.badge.shield.checkmark"
        case .models: "shippingbox"
        case .done: "checkmark.seal"
        }
    }

    /// Steps the owner may leave unfinished; the app explains the gap instead of failing later.
    var isSkippable: Bool {
        self == .microphone || self == .firstMate || self == .models
    }
}

/// Which step is showing and how to move between them.
@MainActor
@Observable
final class OnboardingFlow {
    var step: OnboardingStep = .welcome

    var isFirst: Bool {
        step == .welcome
    }

    var isLast: Bool {
        step == .done
    }

    func next() {
        guard let following = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        step = following
    }

    func back() {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }
}
