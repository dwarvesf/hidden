//
//  PaletteKeyAction.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import AppKit

/// What a key pressed in the palette does besides typing into the search field.
enum PaletteKeyAction: Equatable {
    case moveUp
    case moveDown
    /// Return: open the selected app's own menu.
    case open
    /// Command-Return: move the selected app to the visible section.
    case keepShown
    /// Option-Return: move the selected app to the always-hidden section.
    case alwaysHide
    case close

    /// nil for every key the search field should keep (letters, delete, arrows
    /// sideways). Return on the keypad counts as Return.
    static func resolve(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> PaletteKeyAction? {
        let held = modifiers.intersection(.deviceIndependentFlagsMask).subtracting([.numericPad, .function, .capsLock])
        switch keyCode {
        case 126: return held.isEmpty ? .moveUp : nil
        case 125: return held.isEmpty ? .moveDown : nil
        case 53: return held.isEmpty ? .close : nil
        case 36, 76:
            if held == .command { return .keepShown }
            if held == .option { return .alwaysHide }
            return held.isEmpty ? .open : nil
        default: return nil
        }
    }
}
