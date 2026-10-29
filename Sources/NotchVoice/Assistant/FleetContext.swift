//  FleetContext.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation

/// Read-only fleet context for the assistant, refreshed in the background from the
/// firstmate home's `bin/fm-bearings-snapshot.sh --json`. The snapshot takes many seconds,
/// so a turn never waits for it: it uses the latest summary and states its age. Each run
/// costs over ten seconds of CPU, so it slows down while the owner is not talking.
@MainActor
final class FleetContext {
    static let activeWindow: TimeInterval = 10 * 60

    private(set) var summary: String?
    private(set) var refreshedAt: Date?
    private var loop: Task<Void, Never>?
    private var refreshing = false
    private var home = ""
    private let now: () -> Date
    private var lastUsed: Date
    private var lastAttempt: Date?
    private var activeRate: FleetRefreshRate = .minute
    private var idleRate: FleetRefreshRate = .fourMinutes

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
        lastUsed = now()
    }

    var staleAfterSeconds: Int {
        activeRate.staleAfterSeconds
    }

    func configure(active: FleetRefreshRate, idle: FleetRefreshRate) {
        activeRate = active
        idleRate = idle
    }

    func refreshManually() {
        Task { await refresh() }
    }

    var ageSeconds: Int? {
        refreshedAt.map { Int(now().timeIntervalSince($0)) }
    }

    func start(home: String) {
        if self.home != home {
            summary = nil
            refreshedAt = nil
            lastAttempt = nil
        }
        self.home = home
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if let seconds = interval.seconds,
                   now().timeIntervalSince(lastAttempt ?? .distantPast) >= Double(seconds) {
                    await refresh()
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    private var interval: FleetRefreshRate {
        now().timeIntervalSince(lastUsed) < Self.activeWindow ? activeRate : idleRate
    }

    /// Before a turn: start a refresh when the summary is older than the refresh interval.
    func refreshIfStale() {
        lastUsed = now()
        if let seconds = activeRate.seconds, (ageSeconds ?? .max) >= seconds {
            Task { await refresh() }
        }
    }

    private func refresh() async {
        guard !refreshing, !home.isEmpty else { return }
        refreshing = true
        defer { refreshing = false }
        let started = Date()
        lastAttempt = now()
        let snapshotHome = home
        let script = snapshotHome + "/bin/fm-bearings-snapshot.sh"
        do {
            guard FileManager.default.isExecutableFile(atPath: script) else { throw InboxError.scriptMissing(script) }
            var environment = ProcessInfo.processInfo.environment
            environment["FM_HOME"] = home
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            let result = try await ProcessRunner.run(
                executable: script, arguments: ["--json"], environment: environment
            )
            guard result.status == 0 else {
                throw InboxError.failed(command: "bearings", status: result.status, message: result.stderr)
            }
            let summary = try FleetSummary.make(from: result.stdout)
            guard snapshotHome == home else { return }
            self.summary = summary
            refreshedAt = now()
            EventLog.record("fleet_context_refreshed", [
                "ms": EventLog.milliseconds(from: started), "chars": String(summary.count)
            ])
        } catch {
            Log.app.error("Fleet context refresh failed: \(error.localizedDescription, privacy: .public)")
            EventLog.record("fleet_context_failed", ["ms": EventLog.milliseconds(from: started)])
        }
    }
}
