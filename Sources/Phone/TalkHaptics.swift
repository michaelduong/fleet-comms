//  TalkHaptics.swift
//  FleetCommsPhone
//
//  Created by Michael Duong on 11/17/26.

import UIKit

/// Haptics for the talk button. Played only while the app is on screen; the lock screen has Apple's own chirp.
@MainActor
final class TalkHaptics {
    private let impact = UIImpactFeedbackGenerator(style: .medium)
    private let tick = UIImpactFeedbackGenerator(style: .light)
    private let notify = UINotificationFeedbackGenerator()
    private var holdTimer: Task<Void, Never>?
    private var sentThisTurn = false

    private var onScreen: Bool {
        UIApplication.shared.applicationState == .active
    }

    /// The mic opened; a light tick follows when the press becomes a hold.
    func opened() {
        sentThisTurn = false
        guard onScreen else { return }
        impact.impactOccurred()
        impact.prepare()
        tick.prepare()
        holdTimer?.cancel()
        holdTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(PhoneLink.holdSeconds))
            guard !Task.isCancelled, let self, onScreen else { return }
            tick.impactOccurred(intensity: 0.7)
        }
    }

    /// The turn is over or the press ended; no tick.
    func cancelHold() {
        holdTimer?.cancel()
        holdTimer = nil
    }

    /// The turn was sent: success double tap, once per turn.
    func sent() {
        cancelHold()
        guard !sentThisTurn, onScreen else { return }
        sentThisTurn = true
        notify.notificationOccurred(.success)
    }

    /// The Mac sent the turn by itself, and the phone has not played the send already.
    func sentByMac() {
        sent()
    }

    func warning() {
        guard onScreen else { return }
        notify.notificationOccurred(.warning)
    }

    func error() {
        guard onScreen else { return }
        notify.notificationOccurred(.error)
    }
}
