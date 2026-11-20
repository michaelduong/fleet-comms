//  LiveActivityController.swift
//  FleetCommsPhone
//
//  Created by Michael Duong on 11/17/26.

import ActivityKit
import Foundation

/// Keeps one Live Activity in step with the handset: the first mate's sentence.
@MainActor
final class LiveActivityController {
    private var activityID: String?
    /// Refreshes run one after another, so a late dot step cannot land after a newer state.
    private var tail: Task<Void, Never>?
    private var last: CommsActivityAttributes.ContentState?

    /// `alert` asks iOS to expand the Dynamic Island for this update; it needs an activity already showing.
    func update(_ state: CommsActivityAttributes.ContentState, alert: Bool = false) {
        guard state != last || alert, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        last = state
        let content = ActivityContent(state: state, staleDate: nil)
        // After a relaunch the activity is still on screen; adopt it rather than leave nothing to alert.
        if activityID == nil { activityID = Activity<CommsActivityAttributes>.activities.first?.id }
        if let id = activityID {
            let previous = tail
            let config = alert ? AlertConfiguration(
                title: "First mate", body: LocalizedStringResource(stringLiteral: state.sentence),
                sound: .named("silence.wav")
            ) : nil
            tail = Task { await previous?.value; await Self.push(id, content, config) }
        } else if let activity = try? Activity.request(
            attributes: CommsActivityAttributes(channel: "First mate"), content: content
        ) {
            activityID = activity.id
        }
    }

    func end() {
        guard let id = activityID else { return }
        activityID = nil
        last = nil
        let previous = tail
        tail = Task { await previous?.value; await Self.finish(id) }
    }

    private nonisolated static func push(_ id: String, _ content: ActivityContent<CommsActivityAttributes.ContentState>,
                                        _ alert: AlertConfiguration?) async {
        let activity = Activity<CommsActivityAttributes>.activities.first { $0.id == id }
        if let alert { await activity?.update(content, alertConfiguration: alert) } else { await activity?.update(content) }
    }

    private nonisolated static func finish(_ id: String) async {
        await Activity<CommsActivityAttributes>.activities.first { $0.id == id }?
            .end(nil, dismissalPolicy: .after(.now + 8))
    }
}
