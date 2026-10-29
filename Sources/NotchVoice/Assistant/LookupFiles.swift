//  LookupFiles.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Darwin
import Foundation

/// Descriptor-relative opens keep symlinks and path traversal out of the data boundary,
/// including when a file is replaced between enumeration and reading.
struct LookupFiles {
    struct Record {
        let path: String
        let text: String?
    }

    private static let ignored: Set<String> = [
        "config", "state", "credentials", "secrets", "node_modules", "build", "deriveddata",
        "sourcepackages", "checkouts", "repositories", "vendor", "dist"
    ]
    private static let images: Set<String> = ["png", "jpg", "jpeg", "heic", "webp"]
    private let deadline = ContinuousClock.now + .milliseconds(400)
    private let terms: Set<String>
    private var remaining = 12000
    private var remainingBytes = 16 * 1024 * 1024

    init(terms: Set<String>) {
        self.terms = terms
    }

    mutating func read(dataDirectory: URL) -> [Record] {
        let descriptor = open(dataDirectory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { return [] }
        defer { close(descriptor) }
        return walk(descriptor, prefix: dataDirectory.path, depth: 0)
    }

    private mutating func walk(_ parent: Int32, prefix: String, depth: Int) -> [Record] {
        guard depth < 6 else { return [] }
        let duplicate = dup(parent)
        guard duplicate >= 0 else { return [] }
        guard let directory = fdopendir(duplicate) else {
            close(duplicate)
            return []
        }
        defer { closedir(directory) }
        var records: [Record] = []
        for name in names(in: directory) {
            guard remaining > 0, ContinuousClock.now < deadline else { break }
            remaining -= 1
            let child = openat(parent, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
            guard child >= 0 else { continue }
            defer { close(child) }
            var info = stat()
            guard fstat(child, &info) == 0 else { continue }
            let path = prefix + "/" + name
            if info.st_mode & S_IFMT == S_IFDIR {
                records += walk(child, prefix: path, depth: depth + 1)
            } else if info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1, let record = readFile(
                child,
                path: path,
                size: info.st_size
            ) {
                records.append(record)
            }
        }
        return records
    }

    private func names(in directory: UnsafeMutablePointer<DIR>) -> [String] {
        var names: [String] = []
        while names.count < remaining, ContinuousClock.now < deadline, let entry = readdir(directory) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
            }
            if Self.permitted(name) {
                names.append(name)
            }
        }
        return names.sorted {
            let left = priority($0)
            let right = priority($1)
            return left == right ? $0 < $1 : left > right
        }
    }

    private func priority(_ name: String) -> Int {
        let lower = name.lowercased()
        return terms.filter { lower.contains($0) }.count * 10 + (lower == "report.md" ? 3 : 0)
    }

    private mutating func readFile(_ descriptor: Int32, path: String, size: off_t) -> Record? {
        let fileExtension = URL(fileURLWithPath: path).pathExtension.lowercased()
        if Self.images.contains(fileExtension) {
            return Record(path: path, text: nil)
        }
        guard ["md", "txt"].contains(fileExtension), size <= 256 * 1024,
              size >= 0, remainingBytes >= Int(size) else { return nil }
        remainingBytes -= Int(size)
        var bytes = [UInt8](repeating: 0, count: Int(size))
        let count = bytes.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
        guard count >= 0, let text = String(bytes: bytes.prefix(count), encoding: .utf8) else { return nil }
        return Record(path: path, text: text)
    }

    private static func permitted(_ name: String) -> Bool {
        let lower = name.lowercased()
        guard !lower.hasPrefix("."), !ignored.contains(lower) else { return false }
        return !["credential", "secret", "password", ".env", "token", "private-key"].contains {
            lower.contains($0)
        }
    }
}
