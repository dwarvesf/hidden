import XCTest
@testable import Hidden_Bar

private func makeExtra(appName: String, x: CGFloat, width: CGFloat = 22, height: CGFloat = 22, title: String? = nil) -> MenuBarExtraInfo {
    MenuBarExtraInfo(
        element: AXUIElementCreateApplication(0),
        appName: appName,
        appIcon: nil,
        title: title,
        pid: 0,
        position: CGPoint(x: x, y: 0),
        size: CGSize(width: width, height: height)
    )
}

/// Contract: MenuBarExtraClassifier.classify sorts already-fetched menu-bar
/// extras into hidden-behind-notch vs visible buckets against a boundary,
/// independent of how those extras were fetched (the live AXUIElement
/// enumeration is a separate, non-unit-testable concern).
/// Serves: NotchOverflowController's overflow menu, which needs a correctly
/// ordered, correctly bucketed list to render.
/// Behaviors covered (4): left-of-boundary classifies hidden, at/right-of
/// boundary classifies visible, zero-size extras are excluded from both
/// buckets, and each bucket is ordered closest-to-boundary first.
/// Mock boundary: none — pure function over an array of value-type structs.
final class MenuBarExtraClassifierTests: XCTestCase {

    // Given an extra positioned left of the boundary
    // When classifying
    // Then it lands in the hidden bucket
    func test_extraLeftOfBoundary_isClassifiedHidden() {
        let extra = makeExtra(appName: "LeftApp", x: 100)

        let result = MenuBarExtraClassifier.classify([extra], boundary: 500)

        XCTAssertEqual(result.hidden.map(\.appName), ["LeftApp"], "an extra left of the boundary must be hidden")
        XCTAssertTrue(result.visible.isEmpty, "an extra left of the boundary must not also appear as visible")
    }

    // Given an extra positioned at or right of the boundary
    // When classifying
    // Then it lands in the visible bucket
    func test_extraAtOrRightOfBoundary_isClassifiedVisible() {
        let atBoundary = makeExtra(appName: "AtBoundary", x: 500)
        let rightOfBoundary = makeExtra(appName: "RightApp", x: 900)

        let result = MenuBarExtraClassifier.classify([atBoundary, rightOfBoundary], boundary: 500)

        XCTAssertEqual(Set(result.visible.map(\.appName)), ["AtBoundary", "RightApp"],
                       "extras at or right of the boundary must be visible")
        XCTAssertTrue(result.hidden.isEmpty)
    }

    // Given an extra with zero width or height (a non-rendering placeholder item)
    // When classifying
    // Then it is excluded from both buckets
    func test_zeroSizeExtra_isExcludedFromBothBuckets() {
        let zeroWidth = makeExtra(appName: "ZeroWidth", x: 100, width: 0)
        let zeroHeight = makeExtra(appName: "ZeroHeight", x: 900, height: 0)

        let result = MenuBarExtraClassifier.classify([zeroWidth, zeroHeight], boundary: 500)

        XCTAssertTrue(result.hidden.isEmpty, "a zero-width extra is not a real rendered icon")
        XCTAssertTrue(result.visible.isEmpty, "a zero-height extra is not a real rendered icon")
    }

    // Given multiple extras in each bucket
    // When classifying
    // Then each bucket is ordered closest-to-boundary first (descending X)
    func test_multipleExtrasPerBucket_areOrderedClosestToBoundaryFirst() {
        let far = makeExtra(appName: "Far", x: 50)
        let near = makeExtra(appName: "Near", x: 450)

        let result = MenuBarExtraClassifier.classify([far, near], boundary: 500)

        XCTAssertEqual(result.hidden.map(\.appName), ["Near", "Far"],
                       "hidden extras must be ordered with the one closest to the notch boundary first")
    }
}
