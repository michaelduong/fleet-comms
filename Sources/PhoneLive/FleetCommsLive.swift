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

private extension Color {
    /// Voice-bar teal from the app icon; also the AccentColor in the asset catalog.
    static let brand = Color(red: 7 / 255, green: 230 / 255, blue: 225 / 255)
}

private var brandMark: some View {
    Image("BrandMark")
        .resizable()
        .scaledToFit()
        .frame(width: 18, height: 18)
        .foregroundStyle(Color.brand)
        .accessibilityLabel("Fleet Comms")
}

/// "Listening…" with the dots lit one more at a time; still in always-on mode.
private struct StatusLine: View {
    let title: String
    let dots: Int
    @Environment(\.isLuminanceReduced) private var reduced

    var body: some View {
        HStack(spacing: 0) {
            Text(title)
            ForEach(1 ... 3, id: \.self) { index in
                Text(".").opacity(reduced || index <= dots ? 1 : 0.15)
            }
        }
        .font(.headline)
        .animation(.easeInOut(duration: 0.3), value: dots)
    }
}

struct CommsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CommsActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image("BrandIcon")
                        .resizable()
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 4.5, style: .continuous))
                        .accessibilityLabel("Fleet Comms")
                        .accessibilityIdentifier("live.icon")
                    Text(context.state.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: context.state.icon)
                        .foregroundStyle(context.state.phase == .listening ? Color.red : Color.brand)
                        .accessibilityLabel(context.state.title)
                        .accessibilityIdentifier("live.phase")
                }
                if context.state.phase == .listening || context.state.phase == .thinking {
                    StatusLine(title: context.state.title, dots: context.state.dots)
                } else if !context.state.sentence.isEmpty {
                    Text(context.state.sentence).font(.headline).lineLimit(4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image("BrandIcon")
                        .resizable()
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 4.5, style: .continuous))
                        .accessibilityLabel("Fleet Comms")
                }
                DynamicIslandExpandedRegion(.center) { Text(context.state.title).font(.caption) }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.phase == .listening || context.state.phase == .thinking {
                        StatusLine(title: context.state.title, dots: context.state.dots)
                    } else {
                        Text(context.state.sentence).lineLimit(3)
                    }
                }
            } compactLeading: {
                brandMark
            } compactTrailing: {
                Image(systemName: context.state.icon)
                    .foregroundStyle(context.state.phase == .listening ? Color.red : Color.brand)
            } minimal: {
                brandMark
            }
            .keylineTint(Color.brand)
        }
    }
}
