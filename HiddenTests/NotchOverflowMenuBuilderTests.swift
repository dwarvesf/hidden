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
/// Behaviors covered (5): empty state when nothing is found, section headers
/// carry correct counts, section headers render at full-contrast label color
/// (not the dim secondary/default-disabled style), an extra with an empty
/// title falls back to the app name, and a hidden extra's title is visually
/// distinguished by glyph and weight from a visible one.
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

    // Given a section header (the top title, or a hidden/visible count header)
    // When it's rendered
    // Then it uses full-contrast labelColor, not secondaryLabelColor or
    // AppKit's default dimmed disabled-item style, since the dim style read
    // poorly against a dark selection highlight
    func test_sectionHeaders_useFullContrastLabelColor_notDimmed() {
        let extras = [makeExtra(appName: "HiddenApp", x: 100)]

        let menu = controller.buildOverflowMenu(extras: extras, boundary: 500)

        let header = menu.items.first { $0.title.contains("Hidden Behind Notch") }
        let color = header?.attributedTitle?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertEqual(color, NSColor.labelColor, "a section header must use the normal full-contrast label color")
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
    // Then it's distinguished by a warning glyph and bold weight, not color
    // alone (color-only signaling gives colorblind users nothing, and reads
    // poorly against a dark selection highlight)
    func test_hiddenExtra_isDistinguishedByGlyphAndWeight_notColorAlone() {
        let extras = [makeExtra(appName: "HiddenApp", x: 100)]

        let menu = controller.buildOverflowMenu(extras: extras, boundary: 500)

        let item = menu.items.first { $0.representedObject is MenuBarExtraInfo }
        XCTAssertEqual(item?.attributedTitle?.string, "\u{26A0}\u{FE0F} HiddenApp",
                       "a hidden extra's title must be prefixed with a warning glyph")
        let font = item?.attributedTitle?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font, NSFont.boldSystemFont(ofSize: 13), "a hidden extra's title must be bold")
        let color = item?.attributedTitle?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertEqual(color, NSColor.labelColor, "a hidden extra's title must stay at the normal legible label color")
    }
}
