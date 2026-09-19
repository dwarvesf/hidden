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

    func testOtherMouseEventTogglesSeparators() {
        // Preserves the old else-branch: any non-left/right click lands on the
        // separators toggle.
        XCTAssertEqual(ExpandCollapseActionResolver.action(eventType: .otherMouseUp, optionPressed: false), .toggleSeparators)
    }
}
