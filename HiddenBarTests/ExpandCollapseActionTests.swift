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
}
