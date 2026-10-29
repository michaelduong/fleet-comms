//  SpeechScrollFixture.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/29/26.

import AppKit
import Foundation
@testable import NotchVoice
import SwiftUI
import Testing

@MainActor
final class SpeechScrollFixture {
    static let text = (1 ... 12).map {
        "Passage \($0). The scheduled checks are complete and ready for review."
    }.joined(separator: "\n\n")

    let model: AppModel
    let window: NSWindow
    let host: NSView
    private let defaults: UserDefaults
    private let name = "speech-scroll-\(UUID().uuidString)"

    init() throws {
        defaults = try #require(UserDefaults(suiteName: name))
        defaults.set(true, forKey: AppSettings.Key.fluidSpeechProAdopted)
        defaults.set("", forKey: AppSettings.Key.firstmateHome)
        model = AppModel(settings: AppSettings(defaults: defaults))
        window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 440, height: 400),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.title = "Spoken reply proof"
        host = NSHostingView(rootView: ExpandedContent(model: model)
            .padding(18).frame(width: 440, height: 400, alignment: .top)
            .foregroundStyle(.white).background(.black).environment(\.colorScheme, .dark))
        window.contentView = host
        window.orderFront(nil)
    }

    func close() {
        model.call?.end()
        model.speaker.stop()
        model.collapseTask?.cancel()
        window.orderOut(nil)
        defaults.removePersistentDomain(forName: name)
    }

    var scroll: NSScrollView? {
        findScroll(in: host)
    }

    func capture(_ name: String, root: URL) {
        UICapture.write(window, to: root.appendingPathComponent(name + ".png"))
    }

    private func findScroll(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView {
            return scroll
        }
        return view.subviews.compactMap { findScroll(in: $0) }.first
    }
}
