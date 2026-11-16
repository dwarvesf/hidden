//
//  ExpandCollapseActionTests.swift
//  HiddenBarTests
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import AppKit
import XCTest

final class ExpandCollapseActionTests: XCTestCase {

    // Assistive synthesis (VoiceOver AXPress) produces no NSEvent; a nil event
    // must still toggle the bar, matching a plain left click.
    func testNilEventToggles() {
        XCTAssertEqual(ExpandCollapseActionResolver.action(eventType: nil, optionPressed: false), .toggle)
    }

    func testLeftClickToggles() {
        XCTAssertEqual(ExpandCollapseActionResolver.action(eventType: .leftMouseUp, optionPressed: false), .toggle)
    }

    func testRightClickShowsContextMenu() {
        XCTAssertEqual(ExpandCollapseActionResolver.action(eventType: .rightMouseUp, optionPressed: false), .contextMenu)
    }

    func testOptionLeftTogglesSeparators() {
        XCTAssertEqual(ExpandCollapseActionResolver.action(eventType: .leftMouseUp, optionPressed: true), .toggleSeparators)
    }

    func testShiftLeftTogglesWithFullBar() {
        XCTAssertEqual(ExpandCollapseActionResolver.action(eventType: .leftMouseUp, optionPressed: false, shiftPressed: true), .toggleWithFullBar)
    }

    func testShiftRightStillShowsContextMenu() {
        XCTAssertEqual(ExpandCollapseActionResolver.action(eventType: .rightMouseUp, optionPressed: false, shiftPressed: true), .contextMenu)
    }

    func testOptionWinsOverShift() {
        XCTAssertEqual(ExpandCollapseActionResolver.action(eventType: .leftMouseUp, optionPressed: true, shiftPressed: true), .toggleSeparators)
    }

    func testShiftDetectedFromLiveFlagsWhenEventFlagsAreEmpty() {
        XCTAssertTrue(ExpandCollapseActionResolver.isShiftPressed(eventFlags: [], liveFlags: .shift))
        XCTAssertFalse(ExpandCollapseActionResolver.isShiftPressed(eventFlags: nil, liveFlags: .option))
    }

    func testOptionRightTogglesSeparators() {
        XCTAssertEqual(ExpandCollapseActionResolver.action(eventType: .rightMouseUp, optionPressed: true), .toggleSeparators)
    }

    // #434: on macOS 27 the button's mouse-up event arrives with no modifier
    // flags while Option is physically held; the live flags must still count.
    func testOptionDetectedFromLiveFlagsWhenEventFlagsAreEmpty() {
        XCTAssertTrue(ExpandCollapseActionResolver.isOptionPressed(eventFlags: [], liveFlags: .option))
    }

    func testOptionDetectedFromEventFlags() {
        XCTAssertTrue(ExpandCollapseActionResolver.isOptionPressed(eventFlags: .option, liveFlags: []))
    }

    func testNoOptionWhenNeitherSourceHasIt() {
        XCTAssertFalse(ExpandCollapseActionResolver.isOptionPressed(eventFlags: [], liveFlags: []))
        XCTAssertFalse(ExpandCollapseActionResolver.isOptionPressed(eventFlags: nil, liveFlags: .shift))
    }

    func testOtherMouseEventTogglesSeparators() {
        // Preserves the old else-branch: any non-left/right click lands on the
        // separators toggle.
        XCTAssertEqual(ExpandCollapseActionResolver.action(eventType: .otherMouseUp, optionPressed: false), .toggleSeparators)
    }

    // A right-click shows the context menu and nothing else: it never lets the
    // arrivals question open, and it clears any popover hanging from the arrow.
    func testRightClickNeverOpensTheArrivalsPromptOrAnyPopover() {
        let action = ExpandCollapseActionResolver.action(eventType: .rightMouseUp, optionPressed: false)
        XCTAssertEqual(action, .contextMenu)
        XCTAssertFalse(action.mayShowArrivalsPrompt)
        XCTAssertTrue(action.closesArrowPopovers)
    }

    func testOnlyAPlainLeftClickMayShowTheArrivalsPrompt() {
        let withPrompt = ExpandCollapseAction.allCases.filter { $0.mayShowArrivalsPrompt }
        XCTAssertEqual(withPrompt, [.toggle])
        let closing = ExpandCollapseAction.allCases.filter { $0.closesArrowPopovers }
        XCTAssertEqual(closing, [.contextMenu])
    }

    // The action runs on the mouse-up. A mouse-down or a drag of either button,
    // with or without Option or Shift, must not toggle anything: Option made the
    // down toggle the separators and the up toggle them back.
    func testHalfAClickDoesNothing() {
        let halves: [NSEvent.EventType] = [.rightMouseDown, .rightMouseDragged, .leftMouseDown, .leftMouseDragged]
        for type in halves {
            for option in [false, true] {
                for shift in [false, true] {
                    XCTAssertEqual(ExpandCollapseActionResolver.action(eventType: type, optionPressed: option, shiftPressed: shift),
                                   .ignore, "\(type.rawValue) option \(option) shift \(shift)")
                }
            }
        }
    }
}
