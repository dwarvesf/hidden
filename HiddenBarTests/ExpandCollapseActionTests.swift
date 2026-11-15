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
}

final class FullBarActivationTests: XCTestCase {

    private func run(isMacOS14OrLater: Bool, stillWanted: Bool) -> [String] {
        var log: [String] = []
        var pending: [() -> Void] = []
        FullBarActivation.switchToRegularAndActivate(
            isMacOS14OrLater: isMacOS14OrLater,
            setPolicy: { log.append("policy:\($0 == .regular ? "regular" : "other")") },
            deferToNextTurn: { pending.append($0) },
            stillWanted: { stillWanted },
            activate: { log.append("activate:\($0)") }
        )
        log.append("turn-boundary")
        pending.forEach { $0() }
        return log
    }

    func testPolicyChangesBeforeTheTurnAndActivationComesAfter() {
        XCTAssertEqual(run(isMacOS14OrLater: true, stillWanted: true),
                       ["policy:regular", "turn-boundary", "activate:cooperative"])
    }

    func testMacOS13KeepsTheLegacyCall() {
        XCTAssertEqual(run(isMacOS14OrLater: false, stillWanted: true),
                       ["policy:regular", "turn-boundary", "activate:legacy"])
    }

    func testCollapsedBeforeTheNextTurnSkipsActivation() {
        XCTAssertEqual(run(isMacOS14OrLater: true, stillWanted: false),
                       ["policy:regular", "turn-boundary"])
    }

    func testRequestKindPerOSVersion() {
        XCTAssertEqual(FullBarActivation.request(isMacOS14OrLater: true), .cooperative)
        XCTAssertEqual(FullBarActivation.request(isMacOS14OrLater: false), .legacy)
    }
}
