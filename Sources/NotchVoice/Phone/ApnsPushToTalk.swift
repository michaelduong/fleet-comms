//  ApnsPushToTalk.swift
//  NotchVoice
//
//  Created by Michael Duong on 11/17/26.

import CryptoKit
import Foundation

/// Wakes the phone's Push to Talk channel through Apple's push service so a reply can play while the
/// phone is locked. Needs the owner's APNs auth key; without `apns.json` beside the app's data it does nothing.
struct ApnsPushToTalk: Sendable {
    struct Config: Codable, Sendable {
        var keyPath: String
        var keyID: String
        var teamID: String
        /// The handset's bundle ID; the push topic is this plus `.voip-ptt`.
        var bundleID: String
        var sandbox: Bool?
    }

    static var configURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Fleet Comms/apns.json")
    }

    static func load() -> ApnsPushToTalk? {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(Config.self, from: data) else { return nil }
        return ApnsPushToTalk(config: config)
    }

    let config: Config

    /// ES256 provider token (JWT) signed with the .p8 key.
    func providerToken(now: Date = Date()) throws -> String {
        let pem = try String(contentsOfFile: (config.keyPath as NSString).expandingTildeInPath, encoding: .utf8)
        let key = try P256.Signing.PrivateKey(pemRepresentation: pem)
        func b64(_ data: Data) -> String {
            data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        let header = b64(Data(#"{"alg":"ES256","kid":"\#(config.keyID)"}"#.utf8))
        let claims = b64(Data(#"{"iss":"\#(config.teamID)","iat":\#(Int(now.timeIntervalSince1970))}"#.utf8))
        let signature = try key.signature(for: Data("\(header).\(claims)".utf8))
        return "\(header).\(claims).\(b64(signature.rawRepresentation))"
    }

    func request(token: String, jwt: String) -> URLRequest {
        let host = config.sandbox == false ? "api.push.apple.com" : "api.sandbox.push.apple.com"
        var request = URLRequest(url: URL(string: "https://\(host)/3/device/\(token)")!)
        request.httpMethod = "POST"
        request.setValue("bearer \(jwt)", forHTTPHeaderField: "authorization")
        request.setValue("pushtotalk", forHTTPHeaderField: "apns-push-type")
        request.setValue("\(config.bundleID).voip-ptt", forHTTPHeaderField: "apns-topic")
        request.setValue("10", forHTTPHeaderField: "apns-priority")
        request.setValue("0", forHTTPHeaderField: "apns-expiration")
        request.httpBody = Data("{}".utf8)
        return request
    }

    /// Returns true when Apple accepted the push.
    func wake(token: String) async -> Bool {
        guard let jwt = try? providerToken() else { return false }
        guard let (_, response) = try? await URLSession.shared.data(for: request(token: token, jwt: jwt)),
              let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }
}
