//  MessengerProcess.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation

/// Subscription CLIs without Claude's warm stream protocol run one isolated process per turn.
actor MessengerProcess {
    private let running = ThreadSafeBox<Process?>(nil)
    private var busy = false

    func shutdown() {
        if let process = running.exchange(nil), process.isRunning {
            process.terminate()
        }
    }

    func ask(model: MessengerModel, input: AssistantTurnInput) async throws -> ClaudeAssistant.Turn {
        guard !busy else { throw AssistantError.busy }
        guard let executable = model.executable else { throw AssistantError.cliMissing(model.cli) }
        busy = true
        defer { busy = false }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("fleet-messenger-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let command = try MessengerCommand(model: model, input: input, directory: directory)
        let started = Date()
        let data = try await Self.run(executable: executable, command: command, running: running)
        let reply = try MessengerCommand.reply(from: data, model: model)
        return ClaudeAssistant.Turn(
            reply: reply, firstTokenMs: nil, totalMs: Int(Date().timeIntervalSince(started) * 1000), processTurn: 1
        )
    }

    private static func run(
        executable: String, command: MessengerCommand, running: ThreadSafeBox<Process?>
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try continuation.resume(returning: runBlocking(executable, command: command, running: running))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func runBlocking(
        _ executable: String, command: MessengerCommand, running: ThreadSafeBox<Process?>
    ) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.currentDirectoryURL = command.directory
        process.arguments = command.arguments
        process.environment = command.environment
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let output = Pipe()
        process.standardOutput = output
        let expired = ThreadSafeBox(false)
        try process.run()
        running.value = process
        defer { running.value = nil }
        let deadline = DispatchWorkItem {
            guard process.isRunning else { return }
            expired.value = true
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: deadline)
        defer { deadline.cancel() }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if expired.value {
            throw AssistantError.timedOut
        }
        guard process.terminationStatus == 0 else { throw AssistantError.processEnded }
        return data
    }
}
