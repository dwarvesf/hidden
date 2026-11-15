//
//  PaletteKeyActionTests.swift
//  HiddenBarTests
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import AppKit
import XCTest

/// Contract: Return opens, Command-Return keeps shown, Option-Return always
/// hides, Escape closes, the arrows move; every other key stays in the search field.
/// Serves: PaletteKeyAction.
/// Mock boundary: none.
final class PaletteKeyActionTests: XCTestCase {

    // Given each key code with its modifiers
    // When resolving
    // Then the action is the one the board's key hints name
    func test_keysMapToTheBoardsActions() {
        XCTAssertEqual(PaletteKeyAction.resolve(keyCode: 36, modifiers: []), .open)
        XCTAssertEqual(PaletteKeyAction.resolve(keyCode: 76, modifiers: []), .open, "keypad Enter")
        XCTAssertEqual(PaletteKeyAction.resolve(keyCode: 36, modifiers: .command), .keepShown)
        XCTAssertEqual(PaletteKeyAction.resolve(keyCode: 36, modifiers: .option), .alwaysHide)
        XCTAssertEqual(PaletteKeyAction.resolve(keyCode: 53, modifiers: []), .close)
        XCTAssertEqual(PaletteKeyAction.resolve(keyCode: 126, modifiers: []), .moveUp)
        XCTAssertEqual(PaletteKeyAction.resolve(keyCode: 125, modifiers: []), .moveDown)
    }

    // Given the flags AppKit adds to arrow keys
    // When resolving
    // Then they do not hide the arrow
    func test_arrowKeysCarryFunctionAndNumericPadFlags() {
        XCTAssertEqual(PaletteKeyAction.resolve(keyCode: 125, modifiers: [.function, .numericPad]), .moveDown)
        XCTAssertEqual(PaletteKeyAction.resolve(keyCode: 36, modifiers: [.capsLock]), .open)
    }

    // Given other keys, or a modifier combination the palette does not use
    // When resolving
    // Then nothing: the search field keeps them
    func test_everythingElseStaysInTheSearchField() {
        XCTAssertNil(PaletteKeyAction.resolve(keyCode: 0, modifiers: []), "a letter")
        XCTAssertNil(PaletteKeyAction.resolve(keyCode: 51, modifiers: []), "delete")
        XCTAssertNil(PaletteKeyAction.resolve(keyCode: 123, modifiers: []), "left arrow")
        XCTAssertNil(PaletteKeyAction.resolve(keyCode: 36, modifiers: [.command, .option]))
        XCTAssertNil(PaletteKeyAction.resolve(keyCode: 36, modifiers: .shift))
        XCTAssertNil(PaletteKeyAction.resolve(keyCode: 125, modifiers: .command), "Command-Down is the field's")
    }
}
