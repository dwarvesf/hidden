//
//  PalettePlacementTests.swift
//  HiddenBarTests
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import XCTest

/// Contract: the palette opens under the arrow on the display with the pointer,
/// inside that display's usable area.
/// Serves: PalettePlacement.
/// Mock boundary: none. Screens are rectangles.
final class PalettePlacementTests: XCTestCase {

    private let main = PaletteScreen(frame: CGRect(x: 0, y: 0, width: 1600, height: 1000),
                                     visibleFrame: CGRect(x: 0, y: 0, width: 1600, height: 975))
    private let side = PaletteScreen(frame: CGRect(x: 1600, y: 0, width: 1200, height: 800),
                                     visibleFrame: CGRect(x: 1600, y: 0, width: 1200, height: 775))
    private let size = CGSize(width: 380, height: 200)

    // Given the arrow on the display with the pointer
    // When placing
    // Then the panel is centred under the arrow, just below the menu bar
    func test_centredUnderTheArrow() throws {
        let arrow = CGRect(x: 1300, y: 975, width: 20, height: 25)
        let frame = try XCTUnwrap(PalettePlacement.frame(size: size, arrow: arrow, pointer: CGPoint(x: 100, y: 500), screens: [main, side]))
        XCTAssertEqual(frame.midX, 1310)
        XCTAssertEqual(frame.maxY, 975 - PalettePlacement.gapBelowMenuBar)
        XCTAssertEqual(frame.size, size)
    }

    // Given the pointer on the second display
    // When placing
    // Then the panel opens on that display, not under the arrow's
    func test_followsThePointerDisplay() throws {
        let arrow = CGRect(x: 1300, y: 975, width: 20, height: 25)
        let frame = try XCTUnwrap(PalettePlacement.frame(size: size, arrow: arrow, pointer: CGPoint(x: 2000, y: 400), screens: [main, side]))
        XCTAssertTrue(side.visibleFrame.contains(frame))
        XCTAssertEqual(frame.maxX, side.visibleFrame.maxX - PalettePlacement.edgeMargin, "the arrow is elsewhere: right end of this menu bar")
        XCTAssertEqual(frame.maxY, 775 - PalettePlacement.gapBelowMenuBar)
    }

    // Given an arrow at the very edge
    // When placing
    // Then the panel stays inside the screen
    func test_clampsToTheScreenEdges() throws {
        let right = try XCTUnwrap(PalettePlacement.frame(size: size, arrow: CGRect(x: 1590, y: 975, width: 10, height: 25),
                                                         pointer: CGPoint(x: 5, y: 5), screens: [main]))
        XCTAssertEqual(right.maxX, 1600 - PalettePlacement.edgeMargin)
        let left = try XCTUnwrap(PalettePlacement.frame(size: size, arrow: CGRect(x: 0, y: 975, width: 10, height: 25),
                                                        pointer: CGPoint(x: 5, y: 5), screens: [main]))
        XCTAssertEqual(left.minX, PalettePlacement.edgeMargin)
    }

    // Given no arrow, or no display
    // When placing
    // Then the right end of the bar, or nothing
    func test_noArrowAndNoScreen() throws {
        let frame = try XCTUnwrap(PalettePlacement.frame(size: size, arrow: nil, pointer: CGPoint(x: 5, y: 5), screens: [main]))
        XCTAssertEqual(frame.maxX, 1600 - PalettePlacement.edgeMargin)
        XCTAssertNil(PalettePlacement.frame(size: size, arrow: nil, pointer: .zero, screens: []))
    }

    // Given a pointer outside every display
    // When picking the screen
    // Then the first display
    func test_pointerOffScreen_usesTheFirstDisplay() {
        XCTAssertEqual(PalettePlacement.screen(for: CGPoint(x: -500, y: -500), in: [main, side]), main)
    }
}
