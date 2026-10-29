//  AboutCapture.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

#if DEBUG
    import AppKit

    @MainActor
    enum AboutCapture {
        static func startIfRequested(dependencies: SettingsDependencies) -> Bool {
            guard let path = DeveloperActions.argument("--capture-about") else { return false }
            // Refuse proof in the installed app's settings domain.
            guard Bundle.main.bundleIdentifier?.hasPrefix("com.fleetcomms.proof.") == true else {
                NSApp.terminate(nil)
                return true
            }
            Task {
                do {
                    try await capture(to: URL(fileURLWithPath: path), dependencies: dependencies)
                } catch {
                    try? error.localizedDescription.write(
                        to: URL(fileURLWithPath: path).appendingPathComponent("capture-error.txt"),
                        atomically: true, encoding: .utf8
                    )
                }
                NSApp.terminate(nil)
            }
            return true
        }

        private static func capture(to folder: URL, dependencies: SettingsDependencies) async throws {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let updater = AppUpdater()
            let controller = SettingsWindowController(dependencies: dependencies, updater: updater)
            controller.show(.about)
            for dark in [false, true] {
                let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                NSApp.appearance = appearance
                controller.window?.appearance = appearance
                try await Task.sleep(for: .milliseconds(700))
                let suffix = dark ? "dark" : "light"
                if let window = controller.window {
                    UICapture.write(window, to: folder.appendingPathComponent("about-\(suffix).png"))
                }
                try captureError(updater: updater, to: folder.appendingPathComponent("update-error-\(suffix).png"))
            }
            controller.window?.close()
        }

        private static func captureError(updater: AppUpdater, to url: URL) throws {
            // Sparkle's standard error uses runModal; capture and dismiss inside that modal run loop.
            let timer = Timer(timeInterval: 0.7, repeats: false) { _ in
                MainActor.assumeIsolated {
                    if let alert = NSApp.modalWindow {
                        // Layer rendering omits NSAlert's dark material background.
                        let capture = Process()
                        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                        capture.arguments = ["-x", "-o", "-l", String(alert.windowNumber), url.path]
                        try? capture.run()
                        capture.waitUntilExit()
                        NSApp.abortModal()
                        alert.orderOut(nil)
                    }
                }
            }
            RunLoop.main.add(timer, forMode: .modalPanel)
            updater.checkForUpdates()
            timer.invalidate()
            guard FileManager.default.fileExists(atPath: url.path) else { throw CocoaError(.coderInvalidValue) }
        }
    }
#endif
