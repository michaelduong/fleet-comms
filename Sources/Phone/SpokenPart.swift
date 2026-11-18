//  SpokenPart.swift
//  FleetCommsPhone
//
//  Created by Michael Duong on 11/17/26.

import QuartzCore

/// Where one sentence of the reply sits in the text and in the queued audio.
struct SpokenPart {
    let range: Range<Int>
    let startFrame: Int64
    let frames: Int64
    /// Word starts in reply coordinates (samples since the reply began); nil from an older Mac.
    let words: [PhoneWord]?
}

/// The reply was revealed up to `end` (a UTF-16 offset) at `time` (`CACurrentMediaTime`), so it can fade in.
struct RevealMark: Equatable {
    let end: Int
    let time: Double
}

/// Calls back on every screen refresh while it runs.
@MainActor
final class DisplayTicker: NSObject {
    private var link: CADisplayLink?
    private let tick: @MainActor () -> Void

    init(_ tick: @escaping @MainActor () -> Void) {
        self.tick = tick
        super.init()
        link = CADisplayLink(target: self, selector: #selector(fire))
        link?.add(to: .main, forMode: .common)
    }

    @objc private func fire() {
        tick()
    }

    func stop() {
        link?.invalidate()
        link = nil
    }
}

/// A `part` message waiting for its audio frames.
struct PendingPart {
    let start: Int
    let length: Int
    let words: [PhoneWord]?
}
