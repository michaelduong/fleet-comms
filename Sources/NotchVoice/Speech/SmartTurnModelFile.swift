//  SmartTurnModelFile.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import CryptoKit
import Foundation

/// The published Smart Turn v3.2 CPU weights (int8 ONNX, about 8.7 MB), pinned to one
/// Hugging Face revision and checked by SHA-256, kept in this app's models folder.
enum SmartTurnModelFile {
    static let name = "smart-turn-v3.2-cpu.onnx"
    private static let revision = "f766f81d3cfdf7737ac64aad813d91bbfd56bf93"
    private static let sha256 = "2bb026316b14a660486a75b1733cd3fbab8c2fd0314dc9af7be49f8cca967e4f"
    private static let source = URL(
        string: "https://huggingface.co/pipecat-ai/smart-turn-v3/resolve/\(revision)/\(name)"
    )!

    static func url(root: URL) -> URL {
        root.appendingPathComponent("SmartTurn/\(name)")
    }

    /// Downloads the file once; later calls return the copy on disk.
    static func ensureDownloaded(
        root: URL = ModelLoader.modelsRoot, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let destination = url(root: root)
        if FileManager.default.fileExists(atPath: destination.path) {
            return destination
        }
        let downloaded = try await ProgressDownload.fetch(source, progress: progress)
        defer { try? FileManager.default.removeItem(at: downloaded) }
        let digest = try SHA256.hash(data: Data(contentsOf: downloaded, options: .mappedIfSafe))
        guard digest.map({ String(format: "%02x", $0) }).joined() == sha256 else {
            throw SmartTurnError.checksumMismatch
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(at: downloaded, to: destination)
        return destination
    }
}

/// One download that reports its fraction complete, landing in a temporary file the caller owns.
private final class ProgressDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let progress: @Sendable (Double) -> Void
    private let continuation: CheckedContinuation<URL, Error>
    private let landed = ThreadSafeBox<URL?>(nil)

    private init(progress: @escaping @Sendable (Double) -> Void, continuation: CheckedContinuation<URL, Error>) {
        self.progress = progress
        self.continuation = continuation
    }

    static func fetch(_ source: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let delegate = ProgressDownload(progress: progress, continuation: continuation)
            let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
            session.downloadTask(with: source).resume()
            session.finishTasksAndInvalidate()
        }
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    /// The system deletes `location` when this returns, so it is moved out first.
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let response = downloadTask.response as? HTTPURLResponse, response.statusCode == 200 else { return }
        let kept = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        if (try? FileManager.default.moveItem(at: location, to: kept)) != nil {
            landed.value = kept
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let kept = landed.value {
            continuation.resume(returning: kept)
        } else {
            continuation.resume(throwing: error ?? URLError(.badServerResponse))
        }
    }
}
