//  SpeechEnd.swift
//  FleetCommsPhone
//
//  Created by Michael Duong on 11/18/26.

import Foundation

/// When the phone may call a reply finished. An empty audio queue between two sentences is not the end;
/// only the Mac's speechEnd with nothing left to play is (FLC-38).
enum SpeechEnd {
    static func shouldEnd(speechEnded: Bool, pendingBuffers: Int) -> Bool {
        speechEnded && pendingBuffers == 0
    }
}
