import XCTest
@testable import Hidden_Bar

private func makeItem(bundleIdentifier: String?, x: CGFloat, width: CGFloat = 22, height: CGFloat = 22) -> MenuBarInventoryItem {
    MenuBarInventoryItem(
        bundleIdentifier: bundleIdentifier,
        frame: CGRect(x: x, y: 0, width: width, height: height)
    )
}

/// Contract: MenuBarLayoutResolver.resolve buckets each inventoried menu-bar
/// item into the section its frame sits in, keyed by owning bundle. Bundles in
/// systemItemOwners (MenuBarAgent, Control Center) are macOS's own controls,
/// protected by system item identifiers, so they stay out of the layout;
/// SystemUIServer's legacy Menu Extras (Time Machine...) carry no system item
/// identifier and must be sectioned by position like any other app or they can
/// never be allowed visible.
/// Serves: NativeVisibilityEngine, which keeps only the layout's visible
/// bundles on screen — a SystemUIServer extra excluded here would always be
/// hidden by macOS.
/// Behaviors covered (6): a SystemUIServer item right of the arrow resolves
/// visible, left of the arrow resolves hidden, the most visible of several
/// same-bundle items wins, an item left of the always-hidden separator
/// resolves always hidden, the visible side flips in RTL, and a Control
/// Center item is excluded from the layout entirely.
/// These verify resolution over synthetic inputs only; they do not replace
/// on-device verification that real Menu Extras behave as assumed.
/// Mock boundary: none — pure function over an array of value-type structs.
final class MenuBarLayoutResolverTests: XCTestCase {

    // Given a SystemUIServer Menu Extra positioned right of the arrow (LTR)
    // When resolving the layout
    // Then its bundle lands in the visible section
    func test_systemUIServerItemRightOfArrow_resolvesVisible() {
        let item = makeItem(bundleIdentifier: "com.apple.systemuiserver", x: 600)
        let separator = CGRect(x: 490, y: 0, width: 20, height: 22)

        let layout = MenuBarLayoutResolver.resolve(inventory: [item],
                                                   separatorFrame: separator,
                                                   alwaysHiddenSeparatorFrame: nil,
                                                   isLTR: true,
                                                   excludingBundle: "com.dwarvesv.minimalbar")

        XCTAssertEqual(layout.sections["com.apple.systemuiserver"], .visible,
                       "a SystemUIServer Menu Extra right of the arrow must resolve visible")
        XCTAssertEqual(layout.bundles(in: [.visible]), ["com.apple.systemuiserver"])
    }

    // Given a SystemUIServer Menu Extra positioned left of the arrow (LTR)
    // When resolving the layout
    // Then its bundle lands in the hidden section
    func test_systemUIServerItemLeftOfArrow_resolvesHidden() {
        let item = makeItem(bundleIdentifier: "com.apple.systemuiserver", x: 100)
        let separator = CGRect(x: 490, y: 0, width: 20, height: 22)

        let layout = MenuBarLayoutResolver.resolve(inventory: [item],
                                                   separatorFrame: separator,
                                                   alwaysHiddenSeparatorFrame: nil,
                                                   isLTR: true,
                                                   excludingBundle: "com.dwarvesv.minimalbar")

        XCTAssertEqual(layout.sections["com.apple.systemuiserver"], .hidden,
                       "a SystemUIServer Menu Extra left of the arrow must resolve hidden")
        XCTAssertEqual(layout.bundles(in: [.hidden]), ["com.apple.systemuiserver"])
    }

    // Given a Control Center item positioned right of the arrow (LTR)
    // When resolving the layout
    // Then it is excluded from the layout, protected by its system item ID
    func test_controlCenterItem_isExcludedFromLayout() {
        let item = makeItem(bundleIdentifier: "com.apple.controlcenter", x: 600)
        let separator = CGRect(x: 490, y: 0, width: 20, height: 22)

        let layout = MenuBarLayoutResolver.resolve(inventory: [item],
                                                   separatorFrame: separator,
                                                   alwaysHiddenSeparatorFrame: nil,
                                                   isLTR: true,
                                                   excludingBundle: "com.dwarvesv.minimalbar")

        XCTAssertNil(layout.sections["com.apple.controlcenter"],
                     "a Control Center item must stay out of the layout")
        XCTAssertTrue(layout.sections.isEmpty)
    }

    // Given two SystemUIServer Menu Extras, one left and one right of the
    // arrow (LTR)
    // When resolving the layout
    // Then the bundle lands in the most visible section
    func test_systemUIServerItemsStraddlingArrow_resolvesVisible() {
        let hiddenItem = makeItem(bundleIdentifier: "com.apple.systemuiserver", x: 100)
        let visibleItem = makeItem(bundleIdentifier: "com.apple.systemuiserver", x: 600)
        let separator = CGRect(x: 490, y: 0, width: 20, height: 22)

        let layout = MenuBarLayoutResolver.resolve(inventory: [hiddenItem, visibleItem],
                                                   separatorFrame: separator,
                                                   alwaysHiddenSeparatorFrame: nil,
                                                   isLTR: true,
                                                   excludingBundle: "com.dwarvesv.minimalbar")

        XCTAssertEqual(layout.sections["com.apple.systemuiserver"], .visible,
                       "the most visible item must win, or a kept-visible extra could be hidden by a sibling")
        XCTAssertEqual(layout.bundles(in: [.visible]), ["com.apple.systemuiserver"])
    }

    // Given a SystemUIServer Menu Extra left of the always-hidden separator
    // (LTR)
    // When resolving the layout
    // Then its bundle lands in the always-hidden section
    func test_systemUIServerItemLeftOfAlwaysHiddenSeparator_resolvesAlwaysHidden() {
        let item = makeItem(bundleIdentifier: "com.apple.systemuiserver", x: 100)
        let separator = CGRect(x: 490, y: 0, width: 20, height: 22)
        let alwaysHiddenSeparator = CGRect(x: 300, y: 0, width: 20, height: 22)

        let layout = MenuBarLayoutResolver.resolve(inventory: [item],
                                                   separatorFrame: separator,
                                                   alwaysHiddenSeparatorFrame: alwaysHiddenSeparator,
                                                   isLTR: true,
                                                   excludingBundle: "com.dwarvesv.minimalbar")

        XCTAssertEqual(layout.sections["com.apple.systemuiserver"], .alwaysHidden,
                       "a SystemUIServer Menu Extra left of the always-hidden separator must resolve always hidden")
        XCTAssertEqual(layout.bundles(in: [.alwaysHidden]), ["com.apple.systemuiserver"])
    }

    // Given a SystemUIServer Menu Extra positioned left of the arrow (RTL)
    // When resolving the layout
    // Then its bundle lands in the visible section
    func test_systemUIServerItemLeftOfArrow_resolvesVisibleInRTL() {
        let item = makeItem(bundleIdentifier: "com.apple.systemuiserver", x: 100)
        let separator = CGRect(x: 490, y: 0, width: 20, height: 22)

        let layout = MenuBarLayoutResolver.resolve(inventory: [item],
                                                   separatorFrame: separator,
                                                   alwaysHiddenSeparatorFrame: nil,
                                                   isLTR: false,
                                                   excludingBundle: "com.dwarvesv.minimalbar")

        XCTAssertEqual(layout.sections["com.apple.systemuiserver"], .visible,
                       "in RTL the visible side flips, so left of the arrow must resolve visible")
        XCTAssertEqual(layout.bundles(in: [.visible]), ["com.apple.systemuiserver"])
    }
}
