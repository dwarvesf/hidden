//
//  AccessibilityPermissionTests.swift
//  HiddenBarTests
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import AppKit
import XCTest

private final class FakeTrust: AccessibilityTrustProviding {
    var isTrusted: Bool
    init(_ isTrusted: Bool) { self.isTrusted = isTrusted }
}

final class AccessibilityPermissionTests: XCTestCase {
    private func make(needsPermission: Bool = true, trusted: Bool, notifications: NotificationCenter = NotificationCenter())
        -> (AccessibilityPermission, FakeTrust, counts: () -> (changes: Int, restores: Int)) {
        let trust = FakeTrust(trusted)
        let permission = AccessibilityPermission(needsPermission: needsPermission, trust: trust,
                                                 notifications: notifications, recheckDelay: 0)
        var changes = 0, restores = 0
        permission.onChange = { changes += 1 }
        permission.onRestored = { restores += 1 }
        return (permission, trust, { (changes, restores) })
    }

    // Given the native engine without the grant
    // Then the permission is missing and a click on the expanded arrow opens Preferences
    func testMissingPermissionOpensPreferencesFromTheExpandedArrow() {
        let (permission, _, _) = make(trusted: false)
        XCTAssertTrue(permission.isMissing)
        XCTAssertTrue(permission.arrowClickOpensPreferences(isCollapsed: false))
        XCTAssertFalse(permission.arrowClickOpensPreferences(isCollapsed: true), "expanding needs no permission")
    }

    // Given the grant, or an engine that needs none (legacy, App Store)
    // Then nothing is missing and the arrow keeps its usual action
    func testGrantedOrUnneededPermissionLeavesTheArrowAlone() {
        for (needs, trusted) in [(true, true), (false, false), (false, true)] {
            let (permission, _, _) = make(needsPermission: needs, trusted: trusted)
            XCTAssertFalse(permission.isMissing, "needs=\(needs) trusted=\(trusted)")
            XCTAssertFalse(permission.arrowClickOpensPreferences(isCollapsed: false), "needs=\(needs) trusted=\(trusted)")
        }
    }

    // Given the grant was missing
    // When this app's own grant arrives
    // Then the collapse is retried once, and repeat notifications leave it alone
    func testRestoredPermissionRetriesOnce() {
        let (permission, trust, counts) = make(trusted: false)
        permission.recheck()
        XCTAssertEqual(counts().restores, 0, "still missing")
        trust.isTrusted = true
        permission.recheck()
        permission.recheck()
        XCTAssertEqual(counts().restores, 1)
        XCTAssertEqual(counts().changes, 3, "Preferences refreshes on every notification")
        XCTAssertFalse(permission.isMissing)
    }

    // Given the grant is in place
    // When another app's grant changes (same system notification)
    // Then nothing is retried, so a bar the user expanded stays expanded
    func testOtherAppsGrantChangesDoNotRetry() {
        let (permission, _, counts) = make(trusted: true)
        for _ in 0..<3 { permission.recheck() }
        XCTAssertEqual(counts().restores, 0)
    }

    func testRevokedThenRestoredRetriesAgain() {
        let (permission, trust, counts) = make(trusted: true)
        trust.isTrusted = false
        permission.recheck()
        XCTAssertTrue(permission.isMissing)
        XCTAssertEqual(counts().restores, 0)
        trust.isTrusted = true
        permission.recheck()
        XCTAssertEqual(counts().restores, 1)
    }

    // The legacy engine never watches for the grant, so it can never retry.
    func testUnneededPermissionNeverRetries() {
        let (permission, trust, counts) = make(needsPermission: false, trusted: false)
        trust.isTrusted = true
        permission.recheck()
        XCTAssertEqual(counts().restores, 0)
    }

    // Given the grant was missing
    // When macOS posts its Accessibility notification after the user flips the switch
    // Then the trust is re-read and the collapse retried without a relaunch
    func testSystemNotificationTriggersTheRetry() {
        let center = NotificationCenter()
        let (permission, trust, _) = make(trusted: false, notifications: center)
        let restored = expectation(description: "restored")
        permission.onRestored = { restored.fulfill() }
        trust.isTrusted = true
        center.post(name: AccessibilityPermission.systemChangeNotification, object: nil)
        wait(for: [restored], timeout: 2)
    }

    func testUnneededPermissionDoesNotObserve() {
        let center = NotificationCenter()
        let (permission, trust, counts) = make(needsPermission: false, trusted: false, notifications: center)
        trust.isTrusted = true
        center.post(name: AccessibilityPermission.systemChangeNotification, object: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(counts().changes, 0)
        _ = permission
    }
}
