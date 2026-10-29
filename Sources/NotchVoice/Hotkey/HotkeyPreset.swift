//  HotkeyPreset.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Carbon.HIToolbox

enum HotkeyPreset: String, CaseIterable, Identifiable, Sendable {
    case optionSpace
    case controlOptionSpace
    case shiftCommandSpace
    case optionCommandV

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .optionSpace: "⌥ Space"
        case .controlOptionSpace: "⌃⌥ Space"
        case .shiftCommandSpace: "⇧⌘ Space"
        case .optionCommandV: "⌥⌘ V"
        }
    }

    var keyCode: UInt32 {
        switch self {
        case .optionSpace, .controlOptionSpace, .shiftCommandSpace: UInt32(kVK_Space)
        case .optionCommandV: UInt32(kVK_ANSI_V)
        }
    }

    var carbonModifiers: UInt32 {
        switch self {
        case .optionSpace: UInt32(optionKey)
        case .controlOptionSpace: UInt32(controlKey | optionKey)
        case .shiftCommandSpace: UInt32(shiftKey | cmdKey)
        case .optionCommandV: UInt32(optionKey | cmdKey)
        }
    }
}
