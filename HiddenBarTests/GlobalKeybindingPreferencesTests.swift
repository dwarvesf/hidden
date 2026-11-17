//
//  GlobalKeybindingPreferencesTests.swift
//  HiddenBarTests
//
//  Copyright © 2026 Console Labs. All rights reserved.
//

import XCTest

private func shortcut(_ characters: String, keyCode: UInt32, command: Bool = true, shift: Bool = false) -> GlobalKeybindPreferences {
    GlobalKeybindPreferences(function: false, control: false, command: command, shift: shift, option: false,
                             capsLock: false, carbonFlags: (command ? 0x100 : 0) | (shift ? 0x200 : 0),
                             characters: characters, keyCode: keyCode)
}

final class GlobalKeybindPreferencesTests: XCTestCase {
    // A bare letter is rejected; a modifier, a function key or the return key with a modifier is fine
    func test_isAcceptableNeedsAModifierOrAFunctionKey() {
        XCTAssertFalse(shortcut("k", keyCode: 40, command: false).isAcceptable)
        XCTAssertTrue(shortcut("k", keyCode: 40).isAcceptable)
        let f5 = GlobalKeybindPreferences(function: true, control: false, command: false, shift: false, option: false,
                                          capsLock: false, carbonFlags: 0, characters: nil, keyCode: 96)
        XCTAssertTrue(f5.isAcceptable)
    }

    // Two shortcuts are the same combo when key and modifiers match, whatever character was typed
    func test_isSameComboComparesKeyAndModifiers() {
        XCTAssertTrue(shortcut("k", keyCode: 40).isSameCombo(as: shortcut("K", keyCode: 40)))
        XCTAssertFalse(shortcut("k", keyCode: 40).isSameCombo(as: shortcut("k", keyCode: 38)))
        XCTAssertFalse(shortcut("k", keyCode: 40).isSameCombo(as: shortcut("k", keyCode: 40, shift: true)))
    }
}
