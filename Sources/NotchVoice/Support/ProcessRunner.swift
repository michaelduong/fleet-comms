//  ProcessRunner.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation

struct ProcessResult: Sendable {
    let status: Int32
    let stdout: Data
    let stderr: String
}

enum ProcessRunner {
    static func run(executable: String, arguments: [String], environment: [String: String]) async throws
        -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try continuation.resume(returning: runBlocking(executable, arguments, environment))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func runBlocking(_ executable: String, _ arguments: [String], _ environment: [String: String])
        throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()
        // Read both pipes before waiting so a large output cannot fill a pipe and deadlock.
        let errData = ThreadSafeBox<Data>(Data())
        let errReader = DispatchQueue.global(qos: .utility)
        let group = DispatchGroup()
        group.enter()
        errReader.async {
            errData.value = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()
        let stderr = String(data: errData.value, encoding: .utf8) ?? ""
        return ProcessResult(
            status: process.terminationStatus,
            stdout: outData,
            stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

final class ThreadSafeBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) {
        stored = value
    }

    var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }

    /// Sets a new value and returns the old one in one locked step.
    func exchange(_ newValue: Value) -> Value {
        lock.withLock {
            let old = stored
            stored = newValue
            return old
        }
    }
}
