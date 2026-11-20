//  LiveActivityController.swift
//  FleetCommsPhone
//
//  Created by Michael Duong on 11/17/26.

import ActivityKit
import Foundation
import os

/// Keeps one Live Activity in step with the handset: the first mate's sentence.
@MainActor
final class LiveActivityController {
    /// After a relaunch, reuse the active card so the next off-screen reply has something to update.
    private var activityID: String? = Activity<CommsActivityAttributes>.activities
        .first { $0.activityState == .active }?.id
    /// Refreshes run one after another, so a late dot step cannot land after a newer state.
    private var tail: Task<Void, Never>?
    private var last: CommsActivityAttributes.ContentState?
    /// One log per refused start, until the app is on screen and can try again.
    private var loggedRefusal = false
    #if DEBUG
        private var lastRefusal = ""
    #endif
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "FleetCommsPhone", category: "live")

    /// `alert` asks iOS to expand the Dynamic Island for this update; it needs an activity already showing.
    /// `canStart` is true only while Fleet Comms is on screen: that is when iOS accepts a new card.
    func update(_ state: CommsActivityAttributes.ContentState, alert: Bool = false, canStart: Bool = false) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            #if DEBUG
                lastRefusal = "activities-disabled"
            #endif
            return
        }
        forgetIfEnded()
        if activityID == nil {
            guard canStart || !loggedRefusal else { return }
            start(state)
            return
        }
        guard state != last || alert else { return }
        last = state
        let content = ActivityContent(state: state, staleDate: nil)
        let id = activityID
        let previous = tail
        let config = alert ? AlertConfiguration(
            title: "First mate", body: LocalizedStringResource(stringLiteral: state.sentence),
            sound: .named("silence.wav")
        ) : nil
        tail = Task { await previous?.value; await Self.push(id, content, config) }
    }

    /// iOS or a swipe ends the card. Forget it so the next time the app is on screen starts another.
    private func forgetIfEnded() {
        guard let id = activityID else { return }
        guard let activity = Activity<CommsActivityAttributes>.activities.first(where: { $0.id == id }),
              activity.activityState == .active || activity.activityState == .stale else {
            activityID = nil
            last = nil
            return
        }
    }

    private func start(_ state: CommsActivityAttributes.ContentState) {
        let content = ActivityContent(state: state, staleDate: nil)
        do {
            let activity = try Activity.request(
                attributes: CommsActivityAttributes(channel: "First mate"), content: content
            )
            activityID = activity.id
            last = state
            loggedRefusal = false
        } catch {
            // Off screen, iOS refuses a new card. The next on-screen update starts one.
            #if DEBUG
                lastRefusal = error.localizedDescription
            #endif
            if !loggedRefusal {
                loggedRefusal = true
                log.error("Live Activity request refused: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    #if DEBUG
        var proofLine: String {
            let shown = Activity<CommsActivityAttributes>.activities.map { activity in
                let state = String(describing: activity.activityState)
                return "\(activity.id.prefix(8)) \(state) \(activity.content.state.phase.rawValue)"
            }
            let refusal = lastRefusal.isEmpty ? "" : " refusal=\(lastRefusal)"
            let id = activityID.map { String($0.prefix(8)) } ?? "nil"
            return "id=\(id) shown=[\(shown.joined(separator: ", "))]\(refusal)"
        }
    #endif

    private nonisolated static func push(
        _ id: String?,
        _ content: ActivityContent<CommsActivityAttributes.ContentState>,
        _ alert: AlertConfiguration?
    ) async {
        guard let id else { return }
        let activity = Activity<CommsActivityAttributes>.activities.first { $0.id == id }
        if let alert {
            await activity?.update(content, alertConfiguration: alert)
        } else {
            await activity?.update(content)
        }
    }
}
