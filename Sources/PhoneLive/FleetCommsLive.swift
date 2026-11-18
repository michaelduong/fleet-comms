//  FleetCommsLive.swift
//  FleetCommsPhoneLive
//
//  Created by Michael Duong on 11/17/26.

import ActivityKit
import SwiftUI
import WidgetKit

@main
struct FleetCommsLiveBundle: WidgetBundle {
    var body: some Widget {
        CommsLiveActivity()
    }
}

private extension CommsActivityAttributes.ContentState {
    var title: String {
        switch phase {
        case .listening: "Listening"
        case .thinking: "Thinking"
        case .speaking: "First mate"
        case .idle: "Standing by"
        }
    }

    var icon: String {
        switch phase {
        case .listening: "mic.fill"
        case .thinking: "ellipsis"
        case .speaking: "waveform"
        case .idle: "antenna.radiowaves.left.and.right"
        }
    }
}

struct CommsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CommsActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 6) {
                Label(context.state.title, systemImage: context.state.icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if !context.state.words.isEmpty {
                    Text(context.state.words).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                if !context.state.sentence.isEmpty {
                    Text(context.state.sentence).font(.headline).lineLimit(4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: context.state.icon) }
                DynamicIslandExpandedRegion(.center) { Text(context.state.title).font(.caption) }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.sentence.isEmpty ? context.state.words : context.state.sentence).lineLimit(3)
                }
            } compactLeading: {
                Image(systemName: context.state.icon)
            } compactTrailing: {
                EmptyView()
            } minimal: {
                Image(systemName: context.state.icon)
            }
        }
    }
}
