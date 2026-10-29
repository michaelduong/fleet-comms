//  OnboardingView.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import SwiftUI

/// What the first-run steps read and drive.
@MainActor
struct OnboardingDependencies {
    let settings: AppSettings
    let library: ModelLibrary
    let microphone: MicrophonePermission
    let openSettings: (SettingsSection) -> Void
    let finish: () -> Void
}

/// First run: a rail of steps on the left, one step at a time on the right.
struct OnboardingView: View {
    let dependencies: OnboardingDependencies
    @Bindable var flow: OnboardingFlow

    var body: some View {
        HStack(spacing: 0) {
            rail
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(28)
                Divider()
                buttons
                    .padding(16)
            }
            .background(.background)
        }
        .frame(width: 720, height: 480)
        .accessibilityIdentifier("onboarding.root")
    }

    private var rail: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(OnboardingStep.allCases) { step in
                RailRow(
                    title: step.title, symbol: step.symbol, selected: step == flow.step,
                    identifier: "onboarding.rail.\(step.rawValue)"
                ) { flow.step = step }
            }
            Spacer()
        }
        .padding(14)
        .frame(width: 190)
        .background(.quaternary.opacity(0.4))
    }

    @ViewBuilder
    private var content: some View {
        switch flow.step {
        case .welcome: WelcomeStep()
        case .microphone: MicrophoneStep(permission: dependencies.microphone)
        case .firstMate: FirstMateStep(settings: dependencies.settings)
        case .models: ModelsStep(library: dependencies.library, settings: dependencies.settings)
        case .done: DoneStep(settings: dependencies.settings, openSettings: dependencies.openSettings)
        }
    }

    private var buttons: some View {
        HStack {
            if !flow.isFirst {
                Button("Back") { flow.back() }
                    .accessibilityIdentifier("onboarding.back")
            }
            Spacer()
            if flow.step.isSkippable {
                Button("Skip for now") { flow.next() }
                    .accessibilityIdentifier("onboarding.skip")
            }
            if flow.isLast {
                Button("Finish") { dependencies.finish() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("onboarding.finish")
            } else {
                Button("Continue") { flow.next() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canContinue)
                    .accessibilityIdentifier("onboarding.continue")
            }
        }
    }

    /// A skippable step is only "continued" once it is actually done; otherwise it is skipped.
    private var canContinue: Bool {
        switch flow.step {
        case .microphone: dependencies.microphone.state == .granted
        case .firstMate: dependencies.settings.firstmateHomeIsValid
        case .models: dependencies.library.starterSetInstalled
        case .welcome, .done: true
        }
    }
}

struct OnboardingHeading: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title2.weight(.semibold))
                .accessibilityIdentifier("onboarding.title")
            Text(subtitle)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("onboarding.subtitle")
        }
        .padding(.bottom, 18)
    }
}
