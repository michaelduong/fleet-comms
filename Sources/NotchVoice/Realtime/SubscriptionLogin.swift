//  SubscriptionLogin.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation

/// Reads the vendor CLIs' own stored logins, read-only: the Codex CLI's ChatGPT login for
/// OpenAI Realtime, and the Grok CLI's SuperGrok login for Grok Voice. The token is a bearer
/// credential: it is never logged, copied or written anywhere by this app.
enum SubscriptionLogin {
    struct Token: Sendable, CustomStringConvertible {
        let bearer: String
        let expiresAt: Date?

        var description: String {
            "Token(redacted)"
        }

        func isUsable(at now: Date = Date(), margin: TimeInterval = 60) -> Bool {
            expiresAt.map { $0.timeIntervalSince(now) > margin } ?? true
        }
    }

    enum Status: Equatable {
        case missing
        case expired
        case valid
    }

    static func status(_ provider: RealtimeProvider) -> Status {
        guard let token = stored(provider) else { return .missing }
        return token.isUsable() ? .valid : .expired
    }

    /// A usable token, renewing the Grok login through its own CLI when it is about to expire.
    static func token(for provider: RealtimeProvider) async throws -> Token {
        guard let token = stored(provider) else { throw RealtimeError.loginMissing }
        if token.isUsable(margin: 120) {
            return token
        }
        if provider == .grok {
            await renewGrokLogin()
            if let renewed = stored(provider), renewed.isUsable() {
                return renewed
            }
        }
        throw RealtimeError.loginExpired
    }

    static func stored(_ provider: RealtimeProvider) -> Token? {
        let path = provider == .grok ? grokAuthPath : codexAuthPath
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return provider == .grok ? parseGrok(data) : parseCodex(data)
    }

    static func parseCodex(_ data: Data) -> Token? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (object["auth_mode"] as? String)?.lowercased() == "chatgpt",
              let tokens = object["tokens"] as? [String: Any],
              let access = tokens["access_token"] as? String, !access.isEmpty else { return nil }
        return Token(bearer: access, expiresAt: jwtExpiry(access))
    }

    /// `~/.grok/auth.json` holds one entry per issuer; the access token is its `key`.
    static func parseGrok(_ data: Data) -> Token? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let entry = object.first { $0.key.hasPrefix("https://auth.x.ai") }?.value as? [String: Any]
        guard let key = entry?["key"] as? String, !key.isEmpty else { return nil }
        let stamped = (entry?["expires_at"] as? String).flatMap(parseDate)
        return Token(bearer: key, expiresAt: jwtExpiry(key) ?? stamped)
    }

    /// The `exp` claim, read without verifying the signature; only used to skip a doomed connect.
    static func jwtExpiry(_ token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = claims["exp"] as? Double else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    private static func parseDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    private static var codexAuthPath: String {
        let home = ProcessInfo.processInfo.environment["CODEX_HOME"].flatMap { $0.isEmpty ? nil : $0 }
        return (home ?? NSHomeDirectory() + "/.codex") + "/auth.json"
    }

    private static var grokAuthPath: String {
        NSHomeDirectory() + "/.grok/auth.json"
    }

    /// The Grok CLI renews its own six-hour token when it starts; `grok models` is its quickest
    /// headless command. Waits at most 15 s and never touches the login file itself.
    private static func renewGrokLogin() async {
        let executable = NSHomeDirectory() + "/.grok/bin/grok"
        guard FileManager.default.isExecutableFile(atPath: executable) else { return }
        var inherited = ProcessInfo.processInfo.environment
        inherited["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        let environment = inherited
        let started = Date()
        // A task group would wait for the process even after the timeout, so race by hand.
        let resumed = ThreadSafeBox(false)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resumeOnce: @Sendable () -> Void = {
                let first = resumed.exchange(true) == false
                if first { continuation.resume() }
            }
            Task.detached {
                _ = try? await ProcessRunner.run(
                    executable: executable, arguments: ["models"], environment: environment
                )
                resumeOnce()
            }
            Task.detached {
                try? await Task.sleep(for: .seconds(15))
                resumeOnce()
            }
        }
        EventLog.record("realtime_login_renewed", ["lane": "grok", "ms": EventLog.milliseconds(from: started)])
    }
}
