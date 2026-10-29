//  HotkeyCenter.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Carbon.HIToolbox

/// The talk hotkey, plus Escape, which is claimed only while the pill needs it so
/// other apps keep Escape the rest of the time.
@MainActor
final class HotkeyCenter {
    private var talkKey: GlobalHotKey?
    private var escapeKey: GlobalHotKey?
    private let onTalk: () -> Void
    private let onEscape: () -> Void

    init(onTalk: @escaping () -> Void, onEscape: @escaping () -> Void) {
        self.onTalk = onTalk
        self.onEscape = onEscape
    }

    @discardableResult
    func registerTalk(_ preset: HotkeyPreset) -> Bool {
        talkKey?.unregister()
        talkKey = GlobalHotKey(keyCode: preset.keyCode, modifiers: preset.carbonModifiers, handler: onTalk)
        if talkKey == nil {
            Log.app.error("Could not register hotkey \(preset.title, privacy: .public); another app may own it")
        }
        return talkKey != nil
    }

    func setEscapeEnabled(_ enabled: Bool) {
        if enabled, escapeKey == nil {
            escapeKey = GlobalHotKey(keyCode: UInt32(kVK_Escape), modifiers: 0, handler: onEscape)
        } else if !enabled {
            escapeKey?.unregister()
            escapeKey = nil
        }
    }
}
