//  VoiceSettingsView.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Observation
import SwiftUI

struct VoiceSettingsView: View {
    @Bindable var settings: AppSettings
    @State private var preview = KokoroVoicePreview()

    var body: some View {
        Form {
            Section("Hearing you") {
                Picker("Speech model", selection: $settings.speechModel) {
                    ForEach(speechModels) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("settings.voice.speechModel")
                if FluidSpeechPro.isInstalled {
                    StatusText(
                        tone: .ready, text: "Fluid Speech Pro is installed by FluidVoice and read from its folder.",
                        identifier: "settings.voice.fluidStatus"
                    )
                } else {
                    StatusText(
                        tone: .neutral, text: "Fluid Speech Pro appears here once FluidVoice has installed it.",
                        identifier: "settings.voice.fluidStatus"
                    )
                }
                Picker("End of turn", selection: $settings.endOfTurn) {
                    ForEach(EndOfTurnChoice.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("settings.voice.endOfTurn")
                Picker("Send after silence", selection: $settings.silenceSeconds) {
                    ForEach(SettingsOptions.silenceSeconds, id: \.self) { Text(String(format: "%.1f s", $0)).tag($0) }
                }
                .accessibilityIdentifier("settings.voice.silence")
                SettingsNote(text: endOfTurnNote, identifier: "settings.voice.endOfTurnNote")
            }
            Section("Speaking to you") {
                voicePicker
                if let activity = preview.activity {
                    ProgressView(activity)
                        .controlSize(.small)
                        .accessibilityIdentifier("settings.voice.previewProgress")
                }
                if let error = preview.errorMessage {
                    SettingsNote(text: error, identifier: "settings.voice.previewError")
                }
                Picker("Speech speed", selection: $settings.speechSpeed) {
                    ForEach(SpeechSpeed.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("settings.voice.speed")
                Toggle("Read the whole reply", isOn: $settings.readWholeReply)
                    .accessibilityIdentifier("settings.voice.readWholeReply")
                SettingsNote(
                    text: "Off reads the opening sentence or two and then says “Details on screen”.",
                    identifier: "settings.voice.readWholeReplyNote"
                )
            }
            Section("After a reply") {
                Toggle("Keep listening after a reply", isOn: $settings.keepListeningAfterReply)
                    .accessibilityIdentifier("settings.voice.keepListening")
                SettingsNote(
                    text: "Opens the microphone for the dismissal window once the reply has been spoken, so you can "
                        + "answer without the hotkey. Needs microphone access already granted.",
                    identifier: "settings.voice.keepListeningNote"
                )
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("settings.voice")
        .onChange(of: settings.voiceID) { preview.stop() }
        .onDisappear { preview.stop() }
    }

    private var voicePicker: some View {
        HStack {
            Picker("Voice", selection: $settings.voiceID) {
                ForEach(VoiceChoice.all) { Text($0.title).tag($0.id) }
            }
            .accessibilityIdentifier("settings.voice.voice")
            Button {
                preview.toggle(voiceID: settings.voiceID) { settings.speechSpeed }
            } label: {
                Label(
                    preview.isPlaying ? "Stop preview" : "Preview",
                    systemImage: preview.isPlaying ? "stop.fill" : "play.fill"
                )
            }
            .accessibilityIdentifier("settings.voice.preview")
        }
    }

    /// Fluid Speech Pro is listed only when it can actually load.
    private var speechModels: [SpeechModelChoice] {
        SpeechModelChoice.allCases.filter {
            $0 != .fluidSpeechPro || FluidSpeechPro.isInstalled || settings.speechModel == .fluidSpeechPro
        }
    }

    private var endOfTurnNote: String {
        switch settings.endOfTurn {
        case .silence:
            "A turn ends after this much quiet, or when the realtime model hears the end of an utterance."
        case .smartTurn:
            "Smart Turn judges each pause from your voice; the silence setting stays the hard ceiling."
        }
    }
}

@MainActor
@Observable
final class KokoroVoicePreview {
    private(set) var isPlaying = false
    private(set) var activity: String?
    private(set) var errorMessage: String?
    @ObservationIgnored private var speaker: ReplySpeaker?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    func toggle(voiceID: String, speed: @escaping () -> SpeechSpeed) {
        let wasPlaying = isPlaying
        stop()
        guard !wasPlaying else { return }
        isPlaying = true
        let current = generation
        let speaker = ReplySpeaker()
        speaker.speed = speed
        self.speaker = speaker
        task = Task { [self] in
            do {
                try Task.checkCancellation()
                try await speaker.load(voiceID: voiceID) { [weak self] fraction, activity in
                    Task { @MainActor in
                        guard let self, self.generation == current else { return }
                        self.activity = fraction == 1 ? nil : activity
                    }
                }
                try Task.checkCancellation()
                guard generation == current else { return }
                activity = nil
                speaker.speak(
                    "This is a preview of the selected voice. The update is ready for your review.",
                    onStart: {}, onFinish: { [weak self] in self?.finished(current) }
                )
            } catch is CancellationError {
                return
            } catch {
                guard generation == current else { return }
                errorMessage = "Could not preview voice: \(error.localizedDescription)"
                finished(current)
            }
        }
    }

    func stop() {
        generation += 1
        task?.cancel()
        task = nil
        speaker?.stop()
        speaker = nil
        isPlaying = false
        activity = nil
        errorMessage = nil
    }

    private func finished(_ current: Int) {
        guard generation == current else { return }
        isPlaying = false
        activity = nil
    }
}
