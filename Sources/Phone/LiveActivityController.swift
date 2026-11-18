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

    func update(_ state: CommsActivityAttributes.ContentState) {
        guard state != last, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        last = state
        let content = ActivityContent(state: state, staleDate: nil)
        if let id = activityID {
            let previous = tail
            tail = Task { await previous?.value; await Self.push(id, content) }
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

    private nonisolated static func push(_ id: String, _ content: ActivityContent<CommsActivityAttributes.ContentState>) async {
        await Activity<CommsActivityAttributes>.activities.first { $0.id == id }?.update(content)
    }

    private nonisolated static func finish(_ id: String) async {
        await Activity<CommsActivityAttributes>.activities.first { $0.id == id }?
            .end(nil, dismissalPolicy: .after(.now + 8))
    }
}
