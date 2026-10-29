//  OnboardingFlowTests.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

@testable import NotchVoice
import Testing

@MainActor
struct OnboardingFlowTests {
    @Test func stepsRunInOrderAndStopAtTheEnds() {
        let flow = OnboardingFlow()
        #expect(flow.isFirst)
        flow.back()
        #expect(flow.step == .welcome)
        for expected in OnboardingStep.allCases.dropFirst() {
            flow.next()
            #expect(flow.step == expected)
        }
        #expect(flow.isLast)
        flow.next()
        #expect(flow.step == .done)
        flow.back()
        #expect(flow.step == .models)
    }

    @Test func onlyTheOptionalStepsCanBeSkipped() {
        #expect(OnboardingStep.allCases.filter(\.isSkippable) == [.microphone, .firstMate, .models])
        #expect(Set(OnboardingStep.allCases.map(\.title)).count == OnboardingStep.allCases.count)
        #expect(Set(SettingsSection.allCases.map(\.symbol)).count == SettingsSection.allCases.count)
    }
}
