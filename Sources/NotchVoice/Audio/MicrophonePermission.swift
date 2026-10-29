//  MicrophonePermission.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import AppKit
import AVFoundation
import Observation

/// Microphone access as macOS reports it, with the two ways to change it.
@MainActor
@Observable
final class MicrophonePermission {
    enum State: Equatable {
        case notDetermined
        case granted
        case denied
    }

    private(set) var state: State = MicrophonePermission.current()

    static func current() -> State {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    func refresh() {
        state = Self.current()
    }

    /// Shows the system prompt once; after a denial only System Settings can change it.
    func request() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            Task { @MainActor in self.refresh() }
        }
    }

    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        NSWorkspace.shared.open(url)
    }
}
