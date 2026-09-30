import XCTest

final class AccessibilityPermissionTransitionTests: XCTestCase {
    func testOtherAppsPermissionChangesPreserveAnExpandedBar() {
        var permission = AccessibilityPermissionTransition(isTrusted: true)
        for _ in 0..<3 {
            XCTAssertFalse(permission.permissionWasRestored(isTrusted: true))
        }
    }

    func testMissingPermissionDoesNotRetryCollapse() {
        var permission = AccessibilityPermissionTransition(isTrusted: false)
        XCTAssertFalse(permission.permissionWasRestored(isTrusted: false))
    }

    func testRestoredPermissionRetriesOnce() {
        var permission = AccessibilityPermissionTransition(isTrusted: false)
        XCTAssertTrue(permission.permissionWasRestored(isTrusted: true))
        XCTAssertFalse(permission.permissionWasRestored(isTrusted: true))
    }

    func testRevocationThenRestorationRetriesAgain() {
        var permission = AccessibilityPermissionTransition(isTrusted: true)
        XCTAssertFalse(permission.permissionWasRestored(isTrusted: false))
        XCTAssertFalse(permission.permissionWasRestored(isTrusted: false))
        XCTAssertTrue(permission.permissionWasRestored(isTrusted: true))
        XCTAssertFalse(permission.permissionWasRestored(isTrusted: true))
    }
}
