import XCTest
@testable import Hidden_Bar

/// Contract: NotchGeometry.computeBoundary must tell the notch-overflow
/// feature (#350) where the notch actually is, replacing the reviewer-flagged
/// `screen.frame.width / 8` heuristic that produced the wrong boundary on
/// screens narrower or wider than the size it was tuned against.
/// Serves: NotchOverflowController, which uses the boundary to classify
/// menu-bar extras as hidden-behind-notch vs visible.
/// Behaviors covered (4): no-notch detection, notch detection via
/// safeAreaInsets, boundary sourced from auxiliaryTopRightArea when present,
/// and the fallback boundary when a notch is reported but the aux rect is
/// unavailable (older OS on notch-capable hardware).
/// Mock boundary: none — this is a pure function over caller-supplied screen
/// geometry values, no NSScreen/AppKit call inside the function under test.
final class NotchGeometryTests: XCTestCase {

    // Given a screen reporting no safe-area inset at the top
    // When computing the notch boundary
    // Then hasNotch is false
    func test_screenWithoutSafeAreaInset_reportsNoNotch() {
        let boundary = NotchGeometry.computeBoundary(
            screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
            safeAreaInsetsTop: 0,
            auxiliaryTopRightAreaMinX: nil
        )

        XCTAssertFalse(boundary.hasNotch, "a zero top safe-area inset means the screen has no notch")
    }

    // Given a screen reporting a positive top safe-area inset
    // When computing the notch boundary
    // Then hasNotch is true
    func test_screenWithSafeAreaInset_reportsNotch() {
        let boundary = NotchGeometry.computeBoundary(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            safeAreaInsetsTop: 32,
            auxiliaryTopRightAreaMinX: 810
        )

        XCTAssertTrue(boundary.hasNotch, "a positive top safe-area inset means the screen has a notch")
    }

    // Given a notch screen with a known auxiliaryTopRightArea boundary
    // When computing the notch boundary
    // Then the threshold is exactly that boundary, not a fraction of screen width
    func test_notchScreen_usesAuxiliaryTopRightAreaAsThreshold_notWidthFraction() {
        // Two different screen widths sharing a real reported aux-area boundary
        // regression-guards the exact bug flagged in review: the old
        // `screen.frame.width / 8`-derived value would differ between these,
        // even though the real hardware boundary here does not.
        let narrowerScreen = NotchGeometry.computeBoundary(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            safeAreaInsetsTop: 32,
            auxiliaryTopRightAreaMinX: 810
        )
        let widerScreen = NotchGeometry.computeBoundary(
            screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
            safeAreaInsetsTop: 32,
            auxiliaryTopRightAreaMinX: 810
        )

        XCTAssertEqual(narrowerScreen.overflowThresholdX, 810, "threshold must come straight from the reported aux-area rect")
        XCTAssertEqual(widerScreen.overflowThresholdX, 810, "threshold must not scale with screen width when the real boundary doesn't")
    }

    // Given a notch is reported but no auxiliaryTopRightArea is available
    // When computing the notch boundary
    // Then it falls back to the documented default rather than 0 or a crash
    func test_notchWithoutAuxiliaryArea_fallsBackToDefaultThreshold() {
        let boundary = NotchGeometry.computeBoundary(
            screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
            safeAreaInsetsTop: 32,
            auxiliaryTopRightAreaMinX: nil
        )

        XCTAssertEqual(boundary.overflowThresholdX, NotchGeometry.fallbackThresholdX,
                       "missing aux-area data on a reported notch must degrade to the documented fallback")
    }
}
