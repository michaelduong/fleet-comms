//  RealtimeError.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation

/// Why a realtime call could not start or ended early, reported on screen even when
/// the on-device fallback voice is unavailable.
enum RealtimeError: Error, Equatable {
    case loginMissing
    case loginExpired
    case notEntitled
    case offline
    case mintFailed(Int)
    case timedOut
    case connectionLost
    case audioFailed
    case readingFailed
    case readingMismatch
    case microphonePermission
    case requestRejected
    case responseFailed

    /// A short, text-free code for the event log.
    var code: String {
        switch self {
        case .loginMissing: "login_missing"
        case .loginExpired: "login_expired"
        case .notEntitled: "not_entitled"
        case .offline: "offline"
        case let .mintFailed(status): "mint_failed_\(status)"
        case .timedOut: "timed_out"
        case .connectionLost: "connection_lost"
        case .audioFailed: "audio_failed"
        case .readingFailed: "reading_failed"
        case .readingMismatch: "reading_words_mismatch"
        case .microphonePermission: "microphone_permission"
        case .requestRejected: "request_rejected"
        case .responseFailed: "response_failed"
        }
    }

    /// Completes "<lane> <reason>, so I'm using the on-device assistant."
    func reason(_ provider: RealtimeProvider) -> String {
        switch self {
        case .loginMissing: "has no sign-in on this Mac. Run \(provider.loginCommand)"
        case .loginExpired: "sign-in has expired. Run \(provider.loginCommand)"
        case .notEntitled: "isn't included in your plan"
        case .offline: "can't be reached. Check the network"
        case .mintFailed: "refused the connection"
        case .timedOut: "took too long to connect"
        case .connectionLost: "lost its connection"
        case .audioFailed: "couldn't use the microphone or speakers"
        default: readingReason
        }
    }

    private var readingReason: String {
        switch self {
        case .readingFailed: "couldn't read the supplied message"
        case .readingMismatch: "changed the supplied message while reading it"
        case .microphonePermission: "needs microphone access for follow-up. Enable it in System Settings"
        case .requestRejected: "rejected the voice or session request"
        default: "couldn't finish the spoken response"
        }
    }

    static func from(_ error: Error) -> RealtimeError {
        if let error = error as? RealtimeError {
            return error
        }
        if let error = error as? URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
                 .dnsLookupFailed:
                return .offline
            case .timedOut:
                return .timedOut
            default:
                return .connectionLost
            }
        }
        return .connectionLost
    }
}
