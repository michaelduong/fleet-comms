//  AppUpdater.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import AppKit
import Combine
import Sparkle

struct UpdateConfiguration {
    static let feedURL = URL(
        string: "https://github.com/michaelduong/fleet-comms/releases/latest/download/appcast.xml"
    )!
    static let repositoryURL = URL(string: "https://github.com/michaelduong/fleet-comms")!
    static let holdMessage = "Automatic updates are not enabled in this prerelease build. "
        + "They require the public release and signing setup."

    let enabled: Bool
    let publicKey: String
    let feedURL: URL?

    init(info: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
        enabled = (info["FleetCommsUpdatesEnabled"] as? String) == "YES"
        publicKey = info["SUPublicEDKey"] as? String ?? ""
        feedURL = (info["SUFeedURL"] as? String).flatMap(URL.init(string:))
    }

    var isReady: Bool {
        guard enabled, feedURL == Self.feedURL,
              let bytes = Data(base64Encoded: publicKey), bytes.count == 32 else { return false }
        return bytes.contains { $0 != 0 }
    }
}

@MainActor
final class AppUpdater: ObservableObject {
    @Published private(set) var canCheckForUpdates = true
    let configuration: UpdateConfiguration
    private let controller: SPUStandardUpdaterController

    init(configuration: UpdateConfiguration = UpdateConfiguration()) {
        self.configuration = configuration
        // Never start the scheduler or a network check while the release hold is active.
        controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil
        )
    }

    func start() {
        guard configuration.isReady else { return }
        controller.startUpdater()
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        guard configuration.isReady else {
            let error = NSError(
                domain: "FleetComms.UpdateSetup", code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Updates are not enabled yet.",
                    NSLocalizedRecoverySuggestionErrorKey: UpdateConfiguration.holdMessage
                ]
            )
            controller.userDriver.showUpdaterError(error, acknowledgement: {})
            return
        }
        controller.checkForUpdates(nil)
    }
}
