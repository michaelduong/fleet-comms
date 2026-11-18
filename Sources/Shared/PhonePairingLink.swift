//  PhonePairingLink.swift
//  NotchVoice
//
//  Created by Michael Duong on 11/17/26.

import Foundation

/// What the Mac's QR code carries: where to find the Mac and the one-time secret that proves the scan.
/// Written `fleetcomms://pair?v=1&n=<Mac name>&a=<host,host>&p=<port>&i=<id>&k=<16 bytes, base64url>`.
struct PhonePairingLink: Equatable, Sendable {
    var name: String
    var hosts: [String]
    var port: UInt16
    var id: String
    var key: Data

    var url: URL? {
        var components = URLComponents()
        components.scheme = "fleetcomms"
        components.host = "pair"
        components.queryItems = [
            URLQueryItem(name: "v", value: "1"),
            URLQueryItem(name: "n", value: name),
            URLQueryItem(name: "a", value: hosts.joined(separator: ",")),
            URLQueryItem(name: "p", value: String(port)),
            URLQueryItem(name: "i", value: id),
            URLQueryItem(name: "k", value: Base64URL.encode(key))
        ]
        return components.url
    }

    init(name: String, hosts: [String], port: UInt16, id: String, key: Data) {
        self.name = name
        self.hosts = hosts
        self.port = port
        self.id = id
        self.key = key
    }

    /// Nil for anything that is not a version 1 pairing link, so a stray code is never half-read.
    init?(_ text: String) {
        guard let components = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme == "fleetcomms", components.host == "pair" else { return nil }
        let items = Dictionary((components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        }, uniquingKeysWith: { first, _ in first })
        guard items["v"] == "1", let hostList = items["a"], let port = items["p"].flatMap(UInt16.init),
              let id = items["i"], !id.isEmpty, let key = items["k"].flatMap(Base64URL.decode), key.count == 16
        else { return nil }
        let hosts = hostList.split(separator: ",").map(String.init)
        guard !hosts.isEmpty else { return nil }
        self.init(name: items["n"] ?? "Mac", hosts: hosts, port: port, id: id, key: key)
    }
}

enum Base64URL {
    static func encode(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ text: String) -> Data? {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }
}
