//  ClaudeAssistant.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation

/// One warm `claude` CLI process running Claude Haiku on the signed-in subscription: no API
/// key, tools, MCP servers, settings or hooks. Turns go in one at a time over stream-json, so
/// each pays only model latency, and the process keeps the conversation for follow-ups.
actor ClaudeAssistant {
    struct Turn: Sendable {
        let reply: AssistantReply
        let firstTokenMs: Int?
        let totalMs: Int
        /// 1 for the first turn a process answers, which pays its start-up.
        let processTurn: Int
    }

    static let maxTurnsPerProcess = 24
    static let turnTimeout: Duration = .seconds(20)

    private let directory: URL
    private let model: MessengerModel
    private let lookup: MessengerLookup?
    private let messenger = MessengerProcess()
    private let executable: String
    private var process: Process?
    private var input: FileHandle?
    private var generation = 0
    private var turnsInProcess = 0
    private var sentContext: String?
    private var pending: CheckedContinuation<AssistantReply, Error>?
    private var turnSerial = 0
    private var firstToken: ContinuousClock.Instant?
    private var recentCrashes: [ContinuousClock.Instant] = []
    private var shutDown = false

    init(executable: String, model: MessengerModel = .haiku, directory: URL? = nil, dataDirectory: URL? = nil) {
        self.directory = directory ?? Self.workingDirectory
        self.model = model
        self.executable = executable
        lookup = dataDirectory.map { MessengerLookup(dataDirectory: $0) }
    }

    func ask(_ input: AssistantTurnInput) async throws -> Turn {
        guard pending == nil else { throw AssistantError.busy }
        let start = ContinuousClock.now
        var input = input
        input.pastWork = lookup?.context(for: input)
        if model != .haiku {
            let turn = try await messenger.ask(model: model, input: input)
            return Turn(
                reply: turn.reply,
                firstTokenMs: turn.firstTokenMs,
                totalMs: Self.milliseconds(start, .now),
                processTurn: turn.processTurn
            )
        }
        try startIfNeeded()
        let includeContext = input.fleetContext != sentContext
        let message = AssistantPrompt.message(for: input, fresh: turnsInProcess == 0, includeContext: includeContext)
        sentContext = input.fleetContext
        turnsInProcess += 1
        let processTurn = turnsInProcess
        firstToken = nil
        let reply = try await send(message)
        let turn = Turn(
            reply: reply,
            firstTokenMs: firstToken.map { Self.milliseconds(start, $0) },
            totalMs: Self.milliseconds(start, .now),
            processTurn: processTurn
        )
        if turnsInProcess >= Self.maxTurnsPerProcess {
            recycle()
        }
        return turn
    }

    /// Starts a fresh process now, so the next turn is warm but remembers nothing.
    func recycle() {
        guard model == .haiku else { return }
        stopProcess()
        try? startIfNeeded()
    }

    func shutdown() async {
        await messenger.shutdown()
        shutDown = true
        stopProcess()
    }

    func warmUp() {
        try? startIfNeeded()
    }

    private func send(_ message: String) async throws -> AssistantReply {
        let data = try AssistantWire.userLine(message)
        let current = generation
        turnSerial += 1
        let serial = turnSerial
        return try await withCheckedThrowingContinuation { continuation in
            pending = continuation
            do {
                try input?.write(contentsOf: data)
            } catch {
                fail(AssistantError.processEnded, generation: current)
                return
            }
            Task {
                try? await Task.sleep(for: Self.turnTimeout)
                self.timedOut(turn: serial)
            }
        }
    }

    private func startIfNeeded() throws {
        guard model == .haiku, process == nil else { return }
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw AssistantError.cliMissing(executable)
        }
        // A write to a process that just died must fail with EPIPE, not kill the app.
        signal(SIGPIPE, SIG_IGN)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = AssistantPrompt.arguments()
        process.environment = Self.environment
        process.currentDirectoryURL = directory
        let inPipe = Pipe()
        let outPipe = Pipe()
        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = FileHandle.nullDevice
        generation += 1
        let current = generation
        process.terminationHandler = { [weak self] ended in
            let status = ended.terminationStatus
            Task { await self?.ended(generation: current, status: status) }
        }
        try process.run()
        self.process = process
        input = inPipe.fileHandleForWriting
        turnsInProcess = 0
        sentContext = nil
        Task { await self.read(outPipe.fileHandleForReading, generation: current) }
        EventLog.record("assistant_process_started", ["generation": String(current)])
    }

    private func read(_ output: FileHandle, generation current: Int) async {
        do {
            for try await line in output.bytes.lines {
                handle(AssistantWire.parse(line), generation: current)
            }
        } catch {
            Log.app.error("Assistant output ended: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handle(_ event: AssistantWire.Event, generation current: Int) {
        guard current == generation else { return }
        switch event {
        case .delta:
            if firstToken == nil {
                firstToken = .now
            }
        case let .reply(reply):
            pending?.resume(returning: reply)
            pending = nil
        case let .failed(subtype):
            fail(AssistantError.turnFailed(subtype), generation: current)
        case .other:
            break
        }
    }

    private func timedOut(turn serial: Int) {
        guard serial == turnSerial, pending != nil else { return }
        EventLog.record("assistant_timeout", ["generation": String(generation)])
        fail(AssistantError.timedOut, generation: generation)
        // The process may be wedged mid-turn; a fresh one is safer than waiting on it.
        recycle()
    }

    private func fail(_ error: AssistantError, generation current: Int) {
        guard current == generation else { return }
        pending?.resume(throwing: error)
        pending = nil
    }

    private func ended(generation current: Int, status: Int32) {
        guard current == generation else { return }
        EventLog.record("assistant_process_exited", ["generation": String(current), "status": String(status)])
        fail(AssistantError.processEnded, generation: current)
        process = nil
        input = nil
        restartAfterCrash()
    }

    /// Restarts a process that died on its own, but stops after three deaths in a minute
    /// so a broken install does not spin; the next turn tries again.
    private func restartAfterCrash() {
        guard !shutDown else { return }
        let now = ContinuousClock.now
        recentCrashes = recentCrashes.filter { now - $0 < .seconds(60) } + [now]
        guard recentCrashes.count < 3 else { return }
        Task {
            try? await Task.sleep(for: .seconds(2))
            self.warmUpIfIdle()
        }
    }

    private func warmUpIfIdle() {
        guard !shutDown, process == nil else { return }
        try? startIfNeeded()
    }

    private func stopProcess() {
        generation += 1
        pending?.resume(throwing: AssistantError.processEnded)
        pending = nil
        try? input?.close()
        process?.terminate()
        process = nil
        input = nil
    }
}

extension ClaudeAssistant {
    private static func milliseconds(_ start: ContinuousClock.Instant, _ end: ContinuousClock.Instant) -> Int {
        let elapsed = end - start
        return Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
    }

    /// A minimal environment: the CLI signs in with the subscription login in the keychain,
    /// and no API key from the launching shell can reach it.
    private static var environment: [String: String] {
        let inherited = ProcessInfo.processInfo.environment
        var environment = ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"]
        for key in ["HOME", "USER", "LOGNAME", "TMPDIR", "LANG", "SHELL"] {
            environment[key] = inherited[key]
        }
        return environment
    }

    /// An empty folder, so no project instructions are picked up from the working directory.
    private static let workingDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = appSupport.appendingPathComponent("NotchVoice/Assistant", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()
}

enum AssistantError: LocalizedError {
    case cliMissing(String)
    case busy
    case timedOut
    case processEnded
    case turnFailed(String)

    var errorDescription: String? {
        switch self {
        case let .cliMissing(path): "Messenger CLI not found at \(path). Set it in Settings."
        case .busy: "The assistant is still answering."
        case .timedOut: "The assistant took too long to answer."
        case .processEnded: "The assistant process stopped."
        case let .turnFailed(subtype): "The assistant could not answer (\(subtype))."
        }
    }

    /// A short, text-free code for the event log.
    var code: String {
        switch self {
        case .cliMissing: "cli_missing"
        case .busy: "busy"
        case .timedOut: "timed_out"
        case .processEnded: "process_ended"
        case let .turnFailed(subtype): "turn_failed_\(subtype)"
        }
    }
}
