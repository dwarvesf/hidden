//
//  MacOS27NoticeTests.swift
//  HiddenBarTests
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import XCTest

#if !HIDDENBAR_NATIVE_VISIBILITY

final class MacOS27NoticeTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "MacOS27NoticeTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func policy(os: Int = 27, version: String = "1.11.2") -> MacOS27NoticePolicy {
        MacOS27NoticePolicy(osMajorVersion: os, appVersion: version, defaults: defaults)
    }

    func testNeverShownBeforeMacOS27() {
        XCTAssertFalse(policy(os: 26).shouldShowAtLaunch())
        XCTAssertFalse(policy(os: 15).appliesToThisOS)
    }

    func testShownOnFirstLaunchOnMacOS27() {
        XCTAssertTrue(policy(os: 27).shouldShowAtLaunch())
        XCTAssertTrue(policy(os: 28).shouldShowAtLaunch())
    }

    func testShownOnlyOncePerAppVersion() {
        let current = policy()
        current.recordShown()
        XCTAssertFalse(current.shouldShowAtLaunch())
        XCTAssertFalse(policy().shouldShowAtLaunch(), "state must persist across instances")
    }

    func testShownAgainAfterAppUpdate() {
        policy(version: "1.11.2").recordShown()
        XCTAssertTrue(policy(version: "1.11.3").shouldShowAtLaunch())
    }

    func testDontShowAgainSticksAcrossVersions() {
        policy(version: "1.11.2").suppressForever()
        XCTAssertFalse(policy(version: "1.11.2").shouldShowAtLaunch())
        XCTAssertFalse(policy(version: "1.12.0").shouldShowAtLaunch())
    }

    func testMenuEntryOutlivesDontShowAgain() {
        let current = policy()
        current.suppressForever()
        XCTAssertTrue(current.appliesToThisOS, "the menu item gates on the OS only")
    }
}

#endif
