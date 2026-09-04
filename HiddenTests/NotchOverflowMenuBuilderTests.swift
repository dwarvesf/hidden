import XCTest
@testable import Hidden_Bar

private func makeExtra(appName: String, x: CGFloat, title: String? = nil) -> MenuBarExtraInfo {
    MenuBarExtraInfo(
        element: AXUIElementCreateApplication(0),
        appName: appName,
        appIcon: nil,
        title: title,
        pid: 0,
        position: CGPoint(x: x, y: 0),
        size: CGSize(width: 22, height: 22)
    )
}

/// Contract: NotchOverflowController.buildOverflowMenu must render a
/// correct, inspectable NSMenu from already-classified extras. NSMenu/
/// NSMenuItem construction runs headlessly (no window needed), so this is
/// unit-testable despite living in an AppKit-heavy controller.
/// Serves: the user browsing the overflow menu to find and reach an icon
/// that macOS silently dropped behind the notch.
/// Behaviors covered (4): empty state when nothing is found, section headers
/// carry correct counts, an extra with an empty title falls back to the app
/// name, and a hidden extra's title is visually distinguished (tinted) from
/// a visible one.
/// Mock boundary: extras and boundary are injected directly, bypassing the
/// live AXUIElement enumeration (getAllMenuBarExtras), which is not
/// unit-testable without a real Accessibility-permitted process.
final class NotchOverflowMenuBuilderTests: XCTestCase {

    private var controller: NotchOverflowController!

    override func setUp() {
        super.setUp()
        controller = NotchOverflowController()
    }

    // Given no extras were found
    // When building the overflow menu
    // Then it shows a single disabled empty-state item
    func test_noExtrasFound_showsDisabledEmptyStateItem() {
        let menu = controller.buildOverflowMenu(extras: [], boundary: 500)

        let emptyStateItem = menu.items.first { $0.title.contains("No items found") }
        XCTAssertNotNil(emptyStateItem, "an empty result must surface a message explaining why, not a blank menu")
        XCTAssertEqual(emptyStateItem?.isEnabled, false, "the empty-state message is informational, not actionable")
    }

    // Given a mix of hidden and visible extras
    // When building the overflow menu
    // Then the section headers report the correct counts
    func test_mixOfHiddenAndVisibleExtras_headersShowCorrectCounts() {
        let extras = [
            makeExtra(appName: "Hidden1", x: 100),
            makeExtra(appName: "Hidden2", x: 150),
            makeExtra(appName: "Visible1", x: 900),
        ]

        let menu = controller.buildOverflowMenu(extras: extras, boundary: 500)

        let hiddenHeader = menu.items.first { $0.title.contains("Hidden Behind Notch") }
        let visibleHeader = menu.items.first { $0.title.contains("Visible") && !$0.title.contains("Hidden") }
        XCTAssertEqual(hiddenHeader?.title.contains("2"), true, "two hidden extras must be reflected in the header count")
        XCTAssertEqual(visibleHeader?.title.contains("1"), true, "one visible extra must be reflected in the header count")
    }

    // Given an extra with an empty AX title
    // When building its menu item
    // Then the item falls back to the app's name
    func test_extraWithEmptyTitle_fallsBackToAppName() {
        let extras = [makeExtra(appName: "FallbackApp", x: 900, title: "")]

        let menu = controller.buildOverflowMenu(extras: extras, boundary: 500)

        let item = menu.items.first { $0.representedObject is MenuBarExtraInfo }
        XCTAssertEqual(item?.title, "FallbackApp", "an empty AX title must fall back to the owning app's name")
    }

    // Given a hidden extra
    // When building its menu item
    // Then its title is tinted orange to distinguish it from a visible one
    func test_hiddenExtra_hasTintedAttributedTitle() {
        let extras = [makeExtra(appName: "HiddenApp", x: 100)]

        let menu = controller.buildOverflowMenu(extras: extras, boundary: 500)

        let item = menu.items.first { $0.representedObject is MenuBarExtraInfo }
        let color = item?.attributedTitle?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertEqual(color, NSColor.systemOrange, "a hidden extra's title must be tinted to distinguish it visually from a visible one")
    }
}
