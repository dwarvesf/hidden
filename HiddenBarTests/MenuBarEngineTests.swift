//
//  MenuBarEngineTests.swift
//  HiddenBarTests
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import AppKit
import XCTest

// The engine sources are compiled straight into this bundle (no host app), so
// the tests never put items in the real menu bar, never need Accessibility, and
// never touch the private visibility API.

// MARK: - Fakes

private final class FakeItems: MenuBarItemProvider {
    private let bar = NSStatusBar()
    let toggleItem: NSStatusItem
    let separatorItem: NSStatusItem
    var alwaysHiddenItem: NSStatusItem?

    init() {
        toggleItem = bar.statusItem(withLength: NSStatusItem.variableLength)
        separatorItem = bar.statusItem(withLength: 1)
        alwaysHiddenItem = bar.statusItem(withLength: 20)
    }
}

private final class FakeInventory: MenuBarInventoryProviding {
    var isAuthorized = true
    var items: [MenuBarInventoryItem] = []
    var authorizationRequests = 0
    var snapshots = 0

    func requestAuthorization() {
        authorizationRequests += 1
    }

    func snapshot(completion: @escaping ([MenuBarInventoryItem]) -> Void) {
        snapshots += 1
        completion(items)
    }
}

private final class FakeAssertion: NativeVisibilityAssertion {
    let allowed: [String]
    private(set) var isInvalidated = false
    var onInvalidate: (() -> Void)?

    init(allowed: [String]) {
        self.allowed = allowed
    }

    func invalidate() {
        isInvalidated = true
        onInvalidate?()
    }
}

// Hands every activation to the test, which decides when and how it completes.
private final class FakeVisibility: NativeVisibilityProviding {
    struct Request {
        let systemItems: [Int]
        let bundles: [String]
        let completion: (Result<NativeVisibilityAssertion, Error>) -> Void
    }

    var isAvailable = true
    var requests: [Request] = []

    func activate(allowedSystemItems: [Int],
                  allowedBundleIdentifiers: [String],
                  completion: @escaping (Result<NativeVisibilityAssertion, Error>) -> Void) {
        requests.append(Request(systemItems: allowedSystemItems, bundles: allowedBundleIdentifiers, completion: completion))
    }

    @discardableResult
    func succeed(_ index: Int) -> FakeAssertion {
        let assertion = FakeAssertion(allowed: requests[index].bundles)
        requests[index].completion(.success(assertion))
        return assertion
    }

    func fail(_ index: Int) {
        requests[index].completion(.failure(NSError(domain: "test", code: 1)))
    }
}

// Stands in for the menu-bar clock: the test clicks it and decides when a press
// has been handled.
private final class FakeClock: MenuBarClockProviding {
    var onClick: ((CGPoint) -> Void)?
    // `completion` brings the restriction back; `finished` reports the panel.
    var presses: [(location: CGPoint, mode: ClockPressMode, completion: () -> Void,
                   finished: (ClockPressOutcome) -> Void)] = []

    func press(at location: CGPoint, mode: ClockPressMode,
               restore: @escaping () -> Void, finished: @escaping (ClockPressOutcome) -> Void) {
        presses.append((location, mode, restore, finished))
    }

    var panelOpen = false
    private(set) var panelChecks = 0
    var isNotificationCenterOpen: Bool {
        panelChecks += 1
        return panelOpen
    }

    func click(at location: CGPoint = CGPoint(x: 1900, y: 12)) {
        onClick?(location)
    }
}

private final class FakeCaptureActivity: CaptureActivityMonitoring {
    var isActive = false
    var onChange: (() -> Void)?

    func set(_ active: Bool) {
        isActive = active
        onChange?()
    }
}

private func item(_ bundle: String?, x: CGFloat, width: CGFloat = 24) -> MenuBarInventoryItem {
    return MenuBarInventoryItem(bundleIdentifier: bundle, frame: CGRect(x: x, y: 0, width: width, height: 24))
}

// LTR bar used throughout: always-hidden separator at 1000, the boundary at 1300
// (the separator for the resolver, the arrow for the native engine).
private let alwaysHiddenSeparator = CGRect(x: 1000, y: 0, width: 20, height: 24)
private let separator = CGRect(x: 1300, y: 0, width: 20, height: 24)
// One display that holds every frame above, so engine tests stay off real screens.
private let mainDisplay = MenuBarDisplay(appKitFrame: CGRect(x: 0, y: 0, width: 2000, height: 1000),
                                         primaryDisplayHeight: 1000)

// MARK: - Layout resolver

final class MenuBarLayoutResolverTests: XCTestCase {
    func testLTRSectionsFollowSeparators() {
        let layout = MenuBarLayoutResolver.resolve(
            inventory: [item("com.always", x: 900), item("com.hidden", x: 1100), item("com.visible", x: 1400)],
            separatorFrame: separator, alwaysHiddenSeparatorFrame: alwaysHiddenSeparator,
            isLTR: true, excludingBundle: nil)
        XCTAssertEqual(layout.sections, ["com.always": .alwaysHidden, "com.hidden": .hidden, "com.visible": .visible])
    }

    func testRTLSectionsAreMirrored() {
        // RTL: arrow on the left, separator just right of it, hidden further right.
        let rtlSeparator = CGRect(x: 300, y: 0, width: 20, height: 24)
        let rtlAlwaysHidden = CGRect(x: 600, y: 0, width: 20, height: 24)
        let layout = MenuBarLayoutResolver.resolve(
            inventory: [item("com.visible", x: 200), item("com.hidden", x: 450), item("com.always", x: 700)],
            separatorFrame: rtlSeparator, alwaysHiddenSeparatorFrame: rtlAlwaysHidden,
            isLTR: false, excludingBundle: nil)
        XCTAssertEqual(layout.sections, ["com.always": .alwaysHidden, "com.hidden": .hidden, "com.visible": .visible])
    }

    func testWithoutAlwaysHiddenSeparatorEverythingLeftIsHidden() {
        let layout = MenuBarLayoutResolver.resolve(
            inventory: [item("com.far", x: 100), item("com.near", x: 1200)],
            separatorFrame: separator, alwaysHiddenSeparatorFrame: nil,
            isLTR: true, excludingBundle: nil)
        XCTAssertEqual(layout.sections, ["com.far": .hidden, "com.near": .hidden])
    }

    func testMostVisibleItemWinsForABundle() {
        let layout = MenuBarLayoutResolver.resolve(
            inventory: [item("com.split", x: 1100), item("com.split", x: 1400),
                        item("com.pair", x: 900), item("com.pair", x: 1100)],
            separatorFrame: separator, alwaysHiddenSeparatorFrame: alwaysHiddenSeparator,
            isLTR: true, excludingBundle: nil)
        XCTAssertEqual(layout.sections["com.split"], .visible)
        XCTAssertEqual(layout.sections["com.pair"], .hidden)
    }

    func testSkipsOwnSystemAndUnidentifiedItems() {
        let layout = MenuBarLayoutResolver.resolve(
            inventory: [item("com.dwarvesv.minimalbar", x: 1100), item("com.apple.MenuBarAgent", x: 1100),
                        item(nil, x: 1100), item("com.app", x: 1100)],
            separatorFrame: separator, alwaysHiddenSeparatorFrame: nil,
            isLTR: true, excludingBundle: "com.dwarvesv.minimalbar")
        XCTAssertEqual(layout.sections, ["com.app": .hidden])
    }

    func testBundlesAreFilteredAndSorted() {
        let layout = MenuBarLayout(sections: ["b": .visible, "a": .visible, "c": .hidden, "d": .alwaysHidden])
        XCTAssertEqual(layout.bundles(in: [.visible]), ["a", "b"])
        XCTAssertEqual(layout.bundles(in: [.visible, .hidden]), ["a", "b", "c"])
    }
}

// MARK: - Several displays (#390, #422)

// The test Mac: a 1600x900 primary display and a 900x1600 portrait display to
// its right, arranged so its top sits 358 points above the primary's top.
private let bothDisplays = MenuBarDisplay.displays(screenFrames: [CGRect(x: 0, y: 0, width: 1600, height: 900),
                                                                  CGRect(x: 1600, y: -342, width: 900, height: 1600)])
private let primary = bothDisplays[0]
private let portrait = bothDisplays[1]

// A status item in Accessibility coordinates on a display's menu bar, its
// centre `fromRight` points from that display's right edge.
private func listed(_ bundle: String, on display: MenuBarDisplay, fromRight: CGFloat) -> MenuBarInventoryItem {
    let frame = display.accessibilityFrame
    return MenuBarInventoryItem(bundleIdentifier: bundle,
                                frame: CGRect(x: frame.maxX - fromRight - 12, y: frame.minY + 3, width: 24, height: 24))
}

// The arrow's window in AppKit coordinates on a display's menu bar.
private func arrow(on display: MenuBarDisplay, fromRight: CGFloat) -> CGRect {
    let frame = display.appKitFrame
    return CGRect(x: frame.maxX - fromRight - 10, y: frame.maxY - 24, width: 20, height: 24)
}

final class MultiDisplayLayoutTests: XCTestCase {
    func testAccessibilityFramesStartAtThePrimaryDisplaysTopLeft() {
        XCTAssertEqual(bothDisplays.map(\.appKitFrame), [CGRect(x: 0, y: 0, width: 1600, height: 900),
                                                          CGRect(x: 1600, y: -342, width: 900, height: 1600)])
        XCTAssertEqual(primary.accessibilityFrame, CGRect(x: 0, y: 0, width: 1600, height: 900))
        // Above the primary display, so a negative y. Measured from the topmost
        // display instead, the primary display would move down by 358 points
        // and its menu bar would be on no display.
        XCTAssertEqual(portrait.accessibilityFrame, CGRect(x: 1600, y: -358, width: 900, height: 1600))
    }

    func testFramesAreFoundOnTheDisplayTheyAreOn() {
        XCTAssertEqual(MenuBarDisplay.containing(accessibilityFrame: listed("a", on: primary, fromRight: 150).frame,
                                                 in: bothDisplays), primary)
        XCTAssertEqual(MenuBarDisplay.containing(accessibilityFrame: listed("a", on: portrait, fromRight: 150).frame,
                                                 in: bothDisplays), portrait)
        XCTAssertEqual(MenuBarDisplay.containing(appKitFrame: arrow(on: primary, fromRight: 200), in: bothDisplays), primary)
        XCTAssertEqual(MenuBarDisplay.containing(appKitFrame: arrow(on: portrait, fromRight: 200), in: bothDisplays), portrait)
    }

    // AppKit draws the arrow on the portrait display while Accessibility lists
    // the items on the primary one. Compared as raw x, every item is left of
    // the arrow and the whole bar vanishes on collapse.
    func testArrowOnTheOtherDisplayIsMeasuredFromTheSameEdge() {
        let layout = MenuBarLayoutResolver.resolve(
            inventory: [listed("com.visible", on: primary, fromRight: 150),
                        listed("com.hidden", on: primary, fromRight: 300)],
            separatorFrame: arrow(on: portrait, fromRight: 200), alwaysHiddenSeparatorFrame: nil,
            displays: bothDisplays, isLTR: true, excludingBundle: nil)
        XCTAssertEqual(layout.sections, ["com.visible": .visible, "com.hidden": .hidden])
    }

    // The reverse: compared as raw x, every item is right of the arrow and
    // nothing ever hides.
    func testItemsOnTheOtherDisplayAreMeasuredFromTheSameEdge() {
        let layout = MenuBarLayoutResolver.resolve(
            inventory: [listed("com.visible", on: portrait, fromRight: 150),
                        listed("com.hidden", on: portrait, fromRight: 300)],
            separatorFrame: arrow(on: primary, fromRight: 200), alwaysHiddenSeparatorFrame: nil,
            displays: bothDisplays, isLTR: true, excludingBundle: nil)
        XCTAssertEqual(layout.sections, ["com.visible": .visible, "com.hidden": .hidden])
    }

    func testAlwaysHiddenSeparatorMovesWithTheArrow() {
        let layout = MenuBarLayoutResolver.resolve(
            inventory: [listed("com.visible", on: primary, fromRight: 150),
                        listed("com.hidden", on: primary, fromRight: 300),
                        listed("com.always", on: primary, fromRight: 500)],
            separatorFrame: arrow(on: portrait, fromRight: 200),
            alwaysHiddenSeparatorFrame: arrow(on: portrait, fromRight: 400),
            displays: bothDisplays, isLTR: true, excludingBundle: nil)
        XCTAssertEqual(layout.sections, ["com.visible": .visible, "com.hidden": .hidden, "com.always": .alwaysHidden])
    }

    func testRightToLeftBarsAreMeasuredFromTheLeftEdge() {
        // The arrow is 200 points from the portrait display's left edge, so
        // items nearer than that to the primary's left edge are visible.
        let rtlArrow = CGRect(x: 1600 + 200 - 10, y: 1234, width: 20, height: 24)
        let layout = MenuBarLayoutResolver.resolve(
            inventory: [MenuBarInventoryItem(bundleIdentifier: "com.visible", frame: CGRect(x: 150 - 12, y: 3, width: 24, height: 24)),
                        MenuBarInventoryItem(bundleIdentifier: "com.hidden", frame: CGRect(x: 300 - 12, y: 3, width: 24, height: 24))],
            separatorFrame: rtlArrow, alwaysHiddenSeparatorFrame: nil,
            displays: bothDisplays, isLTR: false, excludingBundle: nil)
        XCTAssertEqual(layout.sections, ["com.visible": .visible, "com.hidden": .hidden])
    }

    // An item outside every display (pushed off a narrow menu bar, or listed
    // mid-reflow) has no known side: it stays visible, and the rest still hide.
    func testItemOnNoDisplayStaysVisibleWithoutStoppingTheRest() {
        let layout = MenuBarLayoutResolver.resolve(
            inventory: [MenuBarInventoryItem(bundleIdentifier: "com.lost", frame: CGRect(x: 600, y: -300, width: 24, height: 24)),
                        listed("com.hidden", on: primary, fromRight: 300)],
            separatorFrame: arrow(on: primary, fromRight: 200), alwaysHiddenSeparatorFrame: nil,
            displays: bothDisplays, isLTR: true, excludingBundle: nil)
        XCTAssertEqual(layout.sections, ["com.lost": .visible, "com.hidden": .hidden])
    }

    func testCollapseOnTwoDisplaysAllowsOnlyWhatIsRightOfTheArrow() {
        let items = FakeItems()
        let inventory = FakeInventory()
        inventory.items = [listed("com.visible", on: primary, fromRight: 150),
                           listed("com.hidden", on: primary, fromRight: 300)]
        let visibility = FakeVisibility()
        let engine = NativeVisibilityEngine(items: items, inventory: inventory, visibility: visibility,
                                            ownBundleIdentifier: "com.dwarvesv.minimalbar",
                                            itemFrame: { _ in arrow(on: portrait, fromRight: 200) },
                                            displays: { bothDisplays }, isLTR: { true })
        engine.collapse { _ in }
        XCTAssertEqual(visibility.requests.first?.bundles, ["com.dwarvesv.minimalbar", "com.visible"])
    }

    // A narrow display's menu bar overflows: macOS shows a chevron and lists
    // only the items that fit, so the read misses apps.
    private let overflow = MenuBarInventoryItem(bundleIdentifier: "com.apple.MenuBarAgent",
                                                frame: CGRect(x: 2200, y: -355, width: 24, height: 24),
                                                systemIdentifier: "menu-bar-overflow-indicator")

    func testOverflowIndicatorMarksTheReadIncompleteAndIsNoItem() {
        let layout = MenuBarLayoutResolver.resolve(
            inventory: [overflow, listed("com.visible", on: portrait, fromRight: 150)],
            separatorFrame: arrow(on: portrait, fromRight: 200), alwaysHiddenSeparatorFrame: nil,
            displays: bothDisplays, isLTR: true, excludingBundle: nil)
        XCTAssertTrue(layout.isIncomplete)
        XCTAssertEqual(layout.sections, ["com.visible": .visible])
        XCTAssertEqual(layout.unprovenVisibleSystemItems, [], "the chevron is not an item macOS could be asked to keep")
    }

    func testIncompleteReadTakesMissingAppsFromAnEarlierRead() {
        let earlier = MenuBarLayout(sections: ["com.kept": .visible, "com.moved": .visible, "com.hidden": .hidden])
        var now = MenuBarLayout(sections: ["com.moved": .hidden])
        now.isIncomplete = true
        XCTAssertEqual(now.fillingIn(from: earlier).sections,
                       ["com.kept": .visible, "com.moved": .hidden, "com.hidden": .hidden])
    }

    private func engineOnBothDisplays(_ inventory: FakeInventory, _ visibility: FakeVisibility, arrowOn display: MenuBarDisplay) -> NativeVisibilityEngine {
        let items = FakeItems()
        return NativeVisibilityEngine(items: items, inventory: inventory, visibility: visibility,
                                      ownBundleIdentifier: "com.dwarvesv.minimalbar",
                                      itemFrame: { _ in arrow(on: display, fromRight: 200) },
                                      displays: { bothDisplays }, isLTR: { true })
    }

    func testOverflowingFirstReadLeavesTheBarWhole() {
        let inventory = FakeInventory()
        inventory.items = [overflow, listed("com.visible", on: portrait, fromRight: 150)]
        let visibility = FakeVisibility()
        let engine = engineOnBothDisplays(inventory, visibility, arrowOn: portrait)
        var result: CollapseResult?
        engine.collapse { result = $0 }
        XCTAssertEqual(result, .unavailable)
        XCTAssertTrue(visibility.requests.isEmpty)
    }

    // Collapsed once on the wide display, then again while the narrow one is
    // active: the apps it could not fit stay allowed instead of vanishing.
    func testOverflowingReadKeepsAppsTheLastCompleteReadSawVisible() {
        let inventory = FakeInventory()
        inventory.items = [listed("com.visible", on: primary, fromRight: 150),
                           listed("com.crowded-out", on: primary, fromRight: 180),
                           listed("com.hidden", on: primary, fromRight: 300)]
        let visibility = FakeVisibility()
        var arrowDisplay = primary
        let items = FakeItems()
        let engine = NativeVisibilityEngine(items: items, inventory: inventory, visibility: visibility,
                                            ownBundleIdentifier: "com.dwarvesv.minimalbar",
                                            itemFrame: { _ in arrow(on: arrowDisplay, fromRight: 200) },
                                            displays: { bothDisplays }, isLTR: { true })
        engine.collapse { _ in }
        visibility.succeed(0)
        engine.expand()

        arrowDisplay = portrait
        inventory.items = [overflow, listed("com.visible", on: portrait, fromRight: 150)]
        engine.collapse { _ in }
        XCTAssertEqual(visibility.requests.last?.bundles, ["com.dwarvesv.minimalbar", "com.crowded-out", "com.visible"])
    }

    func testArrowOnNoDisplayLeavesTheBarWhole() {
        let items = FakeItems()
        let inventory = FakeInventory()
        inventory.items = [listed("com.hidden", on: primary, fromRight: 300)]
        let visibility = FakeVisibility()
        let engine = NativeVisibilityEngine(items: items, inventory: inventory, visibility: visibility,
                                            ownBundleIdentifier: "com.dwarvesv.minimalbar",
                                            itemFrame: { _ in CGRect(x: -10_000, y: -10_000, width: 20, height: 24) },
                                            displays: { bothDisplays }, isLTR: { true })
        var result: CollapseResult?
        engine.collapse { result = $0 }
        XCTAssertEqual(result, .unavailable)
        XCTAssertTrue(visibility.requests.isEmpty)
        XCTAssertEqual(engine.state, .expanded)
    }
}

// MARK: - Fail open (macOS 27 items the allow-list cannot name)

private func systemExtra(_ identifier: String?, x: CGFloat) -> MenuBarInventoryItem {
    return MenuBarInventoryItem(bundleIdentifier: "com.apple.MenuBarAgent",
                                frame: CGRect(x: x, y: 0, width: 22, height: 24),
                                systemIdentifier: identifier)
}

final class FailOpenClassificationTests: XCTestCase {
    private func resolve(_ inventory: [MenuBarInventoryItem], isLTR: Bool = true) -> MenuBarLayout {
        return MenuBarLayoutResolver.resolve(inventory: inventory, separatorFrame: separator,
                                             alwaysHiddenSeparatorFrame: nil, isLTR: isLTR,
                                             excludingBundle: "com.dwarvesv.minimalbar")
    }

    func testOwnerWithoutBundleIdRightOfArrowKeepsBarWhole() {
        let layout = resolve([item(nil, x: 1400), item("com.app", x: 1100)])
        XCTAssertEqual(layout.unnameableVisibleItems.count, 1)
        XCTAssertNotNil(layout.reasonToKeepBarWhole(unkeepableSystemItems: []))
    }

    func testOwnerWithoutBundleIdLeftOfArrowCanBeHidden() {
        let layout = resolve([item(nil, x: 1100)])
        XCTAssertTrue(layout.unnameableVisibleItems.isEmpty)
        XCTAssertNil(layout.reasonToKeepBarWhole(unkeepableSystemItems: []))
    }

    func testUnreadableAppCountsAsVisibleOnBothSides() {
        let unreadable = MenuBarInventoryItem(bundleIdentifier: "com.slow", frame: .zero, isUnreadable: true)
        XCTAssertEqual(resolve([unreadable]).sections["com.slow"], .visible)
        XCTAssertEqual(resolve([unreadable], isLTR: false).sections["com.slow"], .visible)
    }

    func testSystemExtraRightOfArrowIsKeptThroughControlCenter() {
        let layout = resolve([systemExtra("com.apple.menuextra.focusmode", x: 1400),
                              systemExtra("com.apple.menuextra.now-playing", x: 1450)])
        XCTAssertEqual(layout.sections["com.apple.controlcenter"], .visible)
        XCTAssertEqual(layout.unprovenVisibleSystemItems,
                       ["com.apple.menuextra.focusmode", "com.apple.menuextra.now-playing"])
    }

    func testSystemExtraLeftOfArrowCanBeHidden() {
        let layout = resolve([systemExtra("com.apple.menuextra.siri", x: 1100)])
        XCTAssertEqual(layout.sections["com.apple.controlcenter"], .hidden)
        XCTAssertTrue(layout.unprovenVisibleSystemItems.isEmpty)
    }

    func testExtrasCoveredBySystemItemsStayOutOfTheLayout() {
        let layout = resolve([systemExtra("com.apple.menuextra.clock", x: 1400),
                              systemExtra("com.apple.menuextra.wifi", x: 1100),
                              systemExtra(nil, x: 1400)])
        XCTAssertEqual(layout, MenuBarLayout(sections: [:]))
    }

    func testExtraMacOSHidBeforeKeepsBarWholeOnlyWhileVisible() {
        let unkeepable: Set = ["com.apple.menuextra.focusmode"]
        let right = resolve([systemExtra("com.apple.menuextra.focusmode", x: 1400)])
        let left = resolve([systemExtra("com.apple.menuextra.focusmode", x: 1100)])
        XCTAssertNotNil(right.reasonToKeepBarWhole(unkeepableSystemItems: unkeepable))
        XCTAssertNil(left.reasonToKeepBarWhole(unkeepableSystemItems: unkeepable))
    }

    func testMissingSystemItemsAreThoseNoLongerListed() {
        let missing = MenuBarLayoutResolver.missingSystemItems(
            ["com.apple.menuextra.focusmode", "com.apple.menuextra.now-playing"],
            in: [systemExtra("com.apple.menuextra.now-playing", x: 1400), item("com.app", x: 1400)])
        XCTAssertEqual(missing, ["com.apple.menuextra.focusmode"])
    }

    func testNoSystemExtraListedAtAllIsInconclusive() {
        // Seen on 27.2 with the screen locked: MenuBarAgent lists no items.
        let missing = MenuBarLayoutResolver.missingSystemItems(["com.apple.menuextra.focusmode"],
                                                               in: [item("com.app", x: 1400)])
        XCTAssertEqual(missing, [])
    }

    func testScanCoversAppsAndBareExecutablesButNotHelpers() {
        func scans(_ path: String?, _ bundle: String?) -> Bool {
            return AccessibilityMenuBarInventory.mayOwnStatusItems(bundleURL: path.map { URL(fileURLWithPath: $0) },
                                                                   bundleIdentifier: bundle)
        }
        XCTAssertTrue(scans("/Applications/iStat Menus.app", "com.bjango.istatmenus"))
        XCTAssertTrue(scans("/opt/homebrew/bin/python3", nil), "script-run status items have no bundle")
        XCTAssertTrue(scans(nil, nil))
        XCTAssertFalse(scans("/System/Library/Frameworks/WebKit.framework/XPCServices/com.apple.WebKit.GPU.xpc", "com.apple.WebKit.GPU"))
        XCTAssertFalse(scans("/Applications/Notes.app/Contents/PlugIns/Widget.appex", "com.apple.Notes.Widget"))
        XCTAssertFalse(scans(nil, "com.apple.WebKit.WebContent"))
    }
}

// Opt-in ("Show all icons while macOS would also hide one right of the arrow").
final class FailOpenEngineTests: XCTestCase {
    private var items: FakeItems!
    private var inventory: FakeInventory!
    private var visibility: FakeVisibility!

    override func setUp() {
        super.setUp()
        items = FakeItems()
        inventory = FakeInventory()
        visibility = FakeVisibility()
    }

    private func makeEngine() -> NativeVisibilityEngine {
        let items = self.items!
        let engine = NativeVisibilityEngine(items: items, inventory: inventory, visibility: visibility,
                                            ownBundleIdentifier: "com.dwarvesv.minimalbar",
                                            itemFrame: { $0 === items.toggleItem ? separator : alwaysHiddenSeparator },
                                            displays: { [mainDisplay] },
                                            isLTR: { true },
                                            pausesHidingForUnkeepableItems: { true })
        engine.scheduleVisibilityCheck = { $0() }
        return engine
    }

    func testSystemExtraMacOSHidFailsOpenAndIsRemembered() {
        let focus = systemExtra("com.apple.menuextra.focusmode", x: 1400)
        let clock = systemExtra("com.apple.menuextra.clock", x: 1500)
        inventory.items = [focus, clock, item("com.hidden", x: 1100)]
        let engine = makeEngine()
        var results: [CollapseResult] = []
        engine.collapse { results.append($0) }
        XCTAssertEqual(visibility.requests.first?.bundles, ["com.dwarvesv.minimalbar", "com.apple.controlcenter"])

        inventory.items = [clock, item("com.hidden", x: 1100)]
        let hiding = visibility.succeed(0)
        XCTAssertTrue(hiding.isInvalidated, "Focus sits right of the arrow, so nothing may stay hidden")
        XCTAssertEqual(results, [.unavailable])
        XCTAssertEqual(engine.state, .expanded)

        inventory.items = [focus, clock, item("com.hidden", x: 1100)]
        engine.collapse { results.append($0) }
        XCTAssertEqual(visibility.requests.count, 1, "no second flash of a restriction known to hide Focus")
        XCTAssertEqual(results, [.unavailable, .unavailable])

        inventory.items = [systemExtra("com.apple.menuextra.focusmode", x: 1100), clock]
        engine.collapse { results.append($0) }
        XCTAssertEqual(visibility.requests.count, 2, "moved left of the arrow, Focus may be hidden again")
    }

    func testSystemExtraMacOSKeptCollapses() {
        inventory.items = [systemExtra("com.apple.menuextra.now-playing", x: 1400), item("com.hidden", x: 1100)]
        let engine = makeEngine()
        var results: [CollapseResult] = []
        engine.collapse { results.append($0) }
        let hiding = visibility.succeed(0)
        XCTAssertFalse(hiding.isInvalidated)
        XCTAssertEqual(results, [.collapsed])
        XCTAssertEqual(engine.state, .collapsed)
    }

    func testExpandDuringTheCheckDropsIt() {
        inventory.items = [systemExtra("com.apple.menuextra.focusmode", x: 1400)]
        let engine = makeEngine()
        var pendingCheck: (() -> Void)?
        engine.scheduleVisibilityCheck = { pendingCheck = $0 }
        var results: [CollapseResult] = []
        engine.collapse { results.append($0) }
        visibility.succeed(0)
        engine.expand()
        pendingCheck?()
        XCTAssertEqual(results, [])
        XCTAssertEqual(engine.state, .expanded)
    }

    func testMenuBarItemOwnersAreTheAppsTheLastReadListed() {
        inventory.items = [item("com.hidden", x: 1100), item("com.visible", x: 1400)]
        let engine = makeEngine()
        XCTAssertEqual(engine.menuBarItemOwners, [])
        engine.collapse { _ in }
        visibility.succeed(0)
        engine.expand()
        XCTAssertEqual(engine.menuBarItemOwners, ["com.hidden", "com.visible"], "kept while expanded, for auto-collapse")
    }

    func testUnreadableAppIsAllowed() {
        inventory.items = [MenuBarInventoryItem(bundleIdentifier: "com.bjango.istatmenus", frame: .zero, isUnreadable: true)]
        makeEngine().collapse { _ in }
        XCTAssertEqual(visibility.requests.first?.bundles, ["com.dwarvesv.minimalbar", "com.bjango.istatmenus"])
    }
}

// MARK: - Unkeepable items, default (hide as v1.11.1 did)
// Written against the engine API that predates the opt-in, so they also run
// on the always-fail-open build as a negative control.

final class UnkeepableItemsDefaultTests: XCTestCase {
    private var items: FakeItems!
    private var inventory: FakeInventory!
    private var visibility: FakeVisibility!

    override func setUp() {
        super.setUp()
        items = FakeItems()
        inventory = FakeInventory()
        visibility = FakeVisibility()
    }

    private func makeEngine() -> NativeVisibilityEngine {
        let items = self.items!
        let engine = NativeVisibilityEngine(items: items, inventory: inventory, visibility: visibility,
                                            ownBundleIdentifier: "com.dwarvesv.minimalbar",
                                            itemFrame: { $0 === items.toggleItem ? separator : alwaysHiddenSeparator },
                                            displays: { [mainDisplay] },
                                            isLTR: { true })
        engine.scheduleVisibilityCheck = { $0() }
        return engine
    }

    func testSystemExtraMacOSHidDoesNotBlockCollapseByDefault() {
        let focus = systemExtra("com.apple.menuextra.focusmode", x: 1400)
        let clock = systemExtra("com.apple.menuextra.clock", x: 1500)
        inventory.items = [focus, clock, item("com.hidden", x: 1100)]
        let engine = makeEngine()
        var results: [CollapseResult] = []
        engine.collapse { results.append($0) }
        inventory.items = [clock, item("com.hidden", x: 1100)]
        let hiding = visibility.succeed(0)
        XCTAssertFalse(hiding.isInvalidated, "Focus right of the arrow must not stop hiding by default")
        XCTAssertEqual(results, [.collapsed])
        XCTAssertEqual(engine.state, .collapsed)

        engine.expand()
        inventory.items = [focus, clock, item("com.hidden", x: 1100)]
        engine.collapse { results.append($0) }
        XCTAssertEqual(visibility.requests.count, 2, "a known unkeepable extra does not block the next collapse")
        visibility.succeed(1)
        XCTAssertEqual(results, [.collapsed, .collapsed])
    }

    func testOwnerWithoutBundleIdRightOfArrowDoesNotBlockCollapseByDefault() {
        inventory.items = [item(nil, x: 1400), item("com.app", x: 1100)]
        let engine = makeEngine()
        var results: [CollapseResult] = []
        engine.collapse { results.append($0) }
        XCTAssertEqual(visibility.requests.count, 1)
        visibility.succeed(0)
        XCTAssertEqual(results, [.collapsed])
    }

    func testUnreadableAppIsStillAllowedByDefault() {
        inventory.items = [MenuBarInventoryItem(bundleIdentifier: "com.bjango.istatmenus", frame: .zero, isUnreadable: true),
                           item("com.app", x: 1100)]
        makeEngine().collapse { _ in }
        XCTAssertEqual(visibility.requests.first?.bundles, ["com.dwarvesv.minimalbar", "com.bjango.istatmenus"])
    }
}

final class UnkeepableItemsOptInTests: XCTestCase {
    private func collapse(_ inventoryItems: [MenuBarInventoryItem], optIn: Bool) -> (requests: Int, result: CollapseResult?) {
        let items = FakeItems()
        let inventory = FakeInventory()
        inventory.items = inventoryItems
        let visibility = FakeVisibility()
        let engine = NativeVisibilityEngine(items: items, inventory: inventory, visibility: visibility,
                                            ownBundleIdentifier: "com.dwarvesv.minimalbar",
                                            itemFrame: { $0 === items.toggleItem ? separator : alwaysHiddenSeparator },
                                            displays: { [mainDisplay] },
                                            isLTR: { true },
                                            pausesHidingForUnkeepableItems: { optIn })
        engine.scheduleVisibilityCheck = { $0() }
        var result: CollapseResult?
        engine.collapse { result = $0 }
        return (visibility.requests.count, result)
    }

    func testOptInKeepsOwnerWithoutBundleIdRightOfArrowShown() {
        let (requests, result) = collapse([item(nil, x: 1400), item("com.app", x: 1100)], optIn: true)
        XCTAssertEqual(requests, 0, "macOS would hide an item the allow-list cannot name")
        XCTAssertEqual(result, .unavailable)
    }

    func testOptInStillCollapsesWhenTheOwnerIsLeftOfArrow() {
        let (requests, _) = collapse([item(nil, x: 1100), item("com.app", x: 1100)], optIn: true)
        XCTAssertEqual(requests, 1)
    }

    func testOptOffCollapsesWithOwnerWithoutBundleIdRightOfArrow() {
        let (requests, _) = collapse([item(nil, x: 1400), item("com.app", x: 1100)], optIn: false)
        XCTAssertEqual(requests, 1)
    }

    // With the opt-in, a collapse reports back only once the system extras were
    // checked. A clock click must not cancel that check: the collapse would
    // never report back, and the bar could neither collapse nor expand.
    func testClockClickDuringTheCheckLeavesTheCollapseToFinish() {
        let items = FakeItems()
        let inventory = FakeInventory()
        inventory.items = [systemExtra("com.apple.menuextra.focusmode", x: 1400),
                           systemExtra("com.apple.menuextra.clock", x: 1500), item("com.hidden", x: 1100)]
        let visibility = FakeVisibility()
        let clock = FakeClock()
        let engine = NativeVisibilityEngine(items: items, inventory: inventory, visibility: visibility, clock: clock,
                                            ownBundleIdentifier: "com.dwarvesv.minimalbar",
                                            itemFrame: { $0 === items.toggleItem ? separator : alwaysHiddenSeparator },
                                            displays: { [mainDisplay] },
                                            isLTR: { true },
                                            pausesHidingForUnkeepableItems: { true })
        var pendingCheck: (() -> Void)?
        engine.scheduleVisibilityCheck = { pendingCheck = $0 }
        var results: [CollapseResult] = []
        engine.collapse { results.append($0) }
        visibility.succeed(0)
        XCTAssertEqual(engine.state, .calibrating, "the check is still to run")

        clock.click()
        clock.presses.first?.completion()
        if visibility.requests.count > 1 {
            visibility.succeed(1)
        }
        pendingCheck?()

        XCTAssertEqual(results, [.collapsed])
        XCTAssertEqual(engine.state, .collapsed)
    }

    func testHiddenExtrasAreListedForPreferences() {
        let items = FakeItems()
        let inventory = FakeInventory()
        let focus = systemExtra("com.apple.menuextra.focusmode", x: 1400)
        let clock = systemExtra("com.apple.menuextra.clock", x: 1500)
        inventory.items = [focus, clock, item("com.hidden", x: 1100)]
        let visibility = FakeVisibility()
        let engine = NativeVisibilityEngine(items: items, inventory: inventory, visibility: visibility,
                                            ownBundleIdentifier: "com.dwarvesv.minimalbar",
                                            itemFrame: { $0 === items.toggleItem ? separator : alwaysHiddenSeparator },
                                            displays: { [mainDisplay] },
                                            isLTR: { true })
        engine.scheduleVisibilityCheck = { $0() }
        let posted = expectation(forNotification: .unkeepableSystemItemsChanged, object: nil)
        engine.collapse { _ in }
        inventory.items = [clock, item("com.hidden", x: 1100)]
        visibility.succeed(0)
        wait(for: [posted], timeout: 1)
        XCTAssertTrue(NativeVisibilityEngine.knownUnkeepableSystemItems.contains("com.apple.menuextra.focusmode"))
        XCTAssertEqual(NativeVisibilityEngine.displayName(ofSystemItem: "com.apple.menuextra.focusmode"), "Focus")
        XCTAssertEqual(NativeVisibilityEngine.displayName(ofSystemItem: "com.apple.menuextra.user"), "User")
        XCTAssertEqual(NativeVisibilityEngine.displayName(ofSystemItem: "com.apple.menuextra.now-playing"), "Now Playing")
        XCTAssertEqual(NativeVisibilityEngine.displayName(ofSystemItem: "com.apple.menuextra.screen-recording"), "Screen Recording")
    }
}

// MARK: - Native engine

final class NativeVisibilityEngineTests: XCTestCase {
    private var items: FakeItems!
    private var inventory: FakeInventory!
    private var visibility: FakeVisibility!
    private var clock: FakeClock!
    private var capture: FakeCaptureActivity!
    private var time: ManualTime!
    private var expands = 0
    private var collapses = 0

    override func setUp() {
        super.setUp()
        items = FakeItems()
        inventory = FakeInventory()
        inventory.items = [item("com.always", x: 900), item("com.hidden", x: 1100), item("com.visible", x: 1400)]
        visibility = FakeVisibility()
        clock = FakeClock()
        capture = FakeCaptureActivity()
        time = ManualTime()
        expands = 0
        collapses = 0
    }

    private func makeEngine(expandsWhenCaptureStarts: Bool = true) -> NativeVisibilityEngine {
        let items = self.items!
        return NativeVisibilityEngine(items: items, inventory: inventory, visibility: visibility, clock: clock,
                                      captureActivity: capture,
                                      ownBundleIdentifier: "com.dwarvesv.minimalbar",
                                      itemFrame: { $0 === items.toggleItem ? separator : alwaysHiddenSeparator },
                                      displays: { [mainDisplay] },
                                      isLTR: { true },
                                      expandsWhenCaptureStarts: { expandsWhenCaptureStarts })
    }

    func testCollapseKeepsOnlyVisibleAppsAndSystemItems() {
        let engine = makeEngine()
        var results: [CollapseResult] = []
        engine.collapse { results.append($0) }

        XCTAssertEqual(engine.state, .calibrating)
        XCTAssertEqual(visibility.requests.first?.bundles, ["com.dwarvesv.minimalbar", "com.visible"])
        XCTAssertEqual(visibility.requests.first?.systemItems, NativeVisibilityEngine.systemItemsToKeep)
        XCTAssertFalse(items.separatorItem.isVisible, "the arrow is the boundary; no separator needed")

        visibility.succeed(0)
        XCTAssertEqual(engine.state, .collapsed)
        XCTAssertEqual(results, [.collapsed])

        engine.expand()
        XCTAssertFalse(items.separatorItem.isVisible)
    }

    func testAlwaysHiddenSeparatorFollowsTheSectionSetting() {
        let engine = makeEngine()
        engine.updateAlwaysHiddenSection(enabled: false, separatorHidden: false)
        XCTAssertEqual(items.alwaysHiddenItem?.length, 0)

        engine.updateAlwaysHiddenSection(enabled: true, separatorHidden: false)
        XCTAssertEqual(items.alwaysHiddenItem?.length, 20)

        engine.collapse { _ in }
        visibility.succeed(visibility.requests.count - 1)
        XCTAssertEqual(items.alwaysHiddenItem?.length, 0)

        engine.expand()
        XCTAssertEqual(items.alwaysHiddenItem?.length, 20)
    }

    // Hiding the always-hidden section takes its separator with it, as it did
    // before macOS 27; it only goes once the icons are actually hidden.
    func testAlwaysHiddenSeparatorHidesWithItsSection() {
        let engine = makeEngine()
        engine.updateAlwaysHiddenSection(enabled: true, separatorHidden: false)
        XCTAssertEqual(items.alwaysHiddenItem?.length, 20)

        engine.updateAlwaysHiddenSection(enabled: true, separatorHidden: true)
        XCTAssertEqual(items.alwaysHiddenItem?.length, 20, "read where it is before hiding anything")
        visibility.succeed(visibility.requests.count - 1)
        XCTAssertEqual(items.alwaysHiddenItem?.length, 0)
        XCTAssertEqual(items.alwaysHiddenItem?.isVisible, false, "out of the bar, not just zero width")

        engine.collapse { _ in }
        XCTAssertEqual(items.alwaysHiddenItem?.length, 0, "does not flash while collapsing")
        visibility.succeed(visibility.requests.count - 1)

        engine.expand()
        XCTAssertEqual(items.alwaysHiddenItem?.length, 0, "does not flash while expanding")
        visibility.succeed(visibility.requests.count - 1)
        XCTAssertEqual(items.alwaysHiddenItem?.length, 0)

        engine.updateAlwaysHiddenSection(enabled: true, separatorHidden: false)
        XCTAssertEqual(items.alwaysHiddenItem?.length, 20)
        XCTAssertEqual(items.alwaysHiddenItem?.isVisible, true)
    }

    // Enabling the section while collapsed creates a fresh, visible separator;
    // it must leave the bar like the rest of the collapsed section.
    func testAlwaysHiddenSeparatorEnabledWhileCollapsedStaysOutOfTheBar() {
        let engine = makeEngine()
        engine.collapse { _ in }
        visibility.succeed(visibility.requests.count - 1)

        items.alwaysHiddenItem?.isVisible = true
        engine.updateAlwaysHiddenSection(enabled: true, separatorHidden: false)
        XCTAssertEqual(items.alwaysHiddenItem?.length, 0)
        XCTAssertEqual(items.alwaysHiddenItem?.isVisible, false)

        engine.expand()
        XCTAssertEqual(items.alwaysHiddenItem?.length, 20)
        XCTAssertEqual(items.alwaysHiddenItem?.isVisible, true)
    }

    func testAlwaysHiddenSeparatorStaysWhenItsSectionCannotBeHidden() {
        let engine = makeEngine()
        engine.updateAlwaysHiddenSection(enabled: true, separatorHidden: true)
        visibility.fail(visibility.requests.count - 1)
        XCTAssertEqual(items.alwaysHiddenItem?.length, 20)
    }

    func testUnavailableAPIFailsOpen() {
        visibility.isAvailable = false
        let engine = makeEngine()
        var result: CollapseResult?
        engine.collapse { result = $0 }

        XCTAssertEqual(result, .unavailable)
        XCTAssertEqual(engine.state, .unavailable)
        XCTAssertTrue(visibility.requests.isEmpty)
    }

    func testMissingAccessibilityAsksAndRetriesLater() {
        inventory.isAuthorized = false
        let engine = makeEngine()
        var results: [CollapseResult] = []
        engine.collapse { results.append($0) }

        XCTAssertEqual(results, [.unavailable])
        XCTAssertEqual(inventory.authorizationRequests, 1)
        XCTAssertTrue(visibility.requests.isEmpty, "never guess which icons to hide")

        inventory.isAuthorized = true
        engine.collapse { results.append($0) }
        XCTAssertEqual(visibility.requests.count, 1, "works once the permission is granted")
    }

    func testActivationFailureReportsUnavailable() {
        let engine = makeEngine()
        var result: CollapseResult?
        engine.collapse { result = $0 }
        visibility.fail(0)

        XCTAssertEqual(result, .unavailable)
        XCTAssertEqual(engine.state, .expanded)
        XCTAssertEqual(items.alwaysHiddenItem?.length, 0, "the always-hidden separator only shows when enabled")
    }

    func testExpandDropsTheRestriction() {
        let engine = makeEngine()
        engine.collapse { _ in }
        let collapsed = visibility.succeed(0)

        engine.expand()
        XCTAssertTrue(collapsed.isInvalidated)
        XCTAssertEqual(engine.state, .expanded)
        XCTAssertEqual(visibility.requests.count, 1)
    }

    func testExpandKeepsAlwaysHiddenSectionHiddenAndSwapsWithoutFlashing() {
        let engine = makeEngine()
        engine.updateAlwaysHiddenSection(enabled: true, separatorHidden: true)
        // Expanded with separators hidden: everything but always-hidden is shown.
        XCTAssertEqual(visibility.requests.last?.bundles, ["com.dwarvesv.minimalbar", "com.hidden", "com.visible"])
        visibility.succeed(visibility.requests.count - 1)

        engine.collapse { _ in }
        let collapseIndex = visibility.requests.count - 1
        XCTAssertEqual(visibility.requests[collapseIndex].bundles, ["com.dwarvesv.minimalbar", "com.visible"])
        let collapsed = visibility.succeed(collapseIndex)

        var newIsActiveWhenOldDropped = false
        collapsed.onInvalidate = { newIsActiveWhenOldDropped = true }
        engine.expand()
        let expandIndex = visibility.requests.count - 1
        XCTAssertEqual(visibility.requests[expandIndex].bundles, ["com.dwarvesv.minimalbar", "com.hidden", "com.visible"])
        XCTAssertFalse(collapsed.isInvalidated, "the old restriction stays until the new one is active")
        visibility.succeed(expandIndex)
        XCTAssertTrue(newIsActiveWhenOldDropped)
    }

    func testSectionsAreNotReadWhileSomethingIsHidden() {
        let engine = makeEngine()
        engine.updateAlwaysHiddenSection(enabled: true, separatorHidden: true)
        visibility.succeed(visibility.requests.count - 1)
        let snapshotsBefore = inventory.snapshots

        // Hidden items would report stale positions now; the cached layout is used.
        inventory.items = [item("com.visible", x: 100)]
        engine.collapse { _ in }
        XCTAssertEqual(inventory.snapshots, snapshotsBefore)
        XCTAssertEqual(visibility.requests.last?.bundles, ["com.dwarvesv.minimalbar", "com.visible"])
    }

    func testExpandDuringActivationDropsTheLateResult() {
        let engine = makeEngine()
        var results: [CollapseResult] = []
        engine.collapse { results.append($0) }

        engine.expand()
        let late = visibility.succeed(0)

        XCTAssertTrue(late.isInvalidated, "a restriction nobody wants any more is released")
        XCTAssertEqual(engine.state, .expanded)
        XCTAssertEqual(results, [])
    }

    func testDisplayChangeKeepsTheBarCollapsed() {
        let engine = makeEngine()
        engine.collapse { _ in }
        let collapsed = visibility.succeed(0)

        engine.invalidateLayout()
        XCTAssertEqual(engine.state, .collapsed)
        XCTAssertFalse(collapsed.isInvalidated)
    }

    // MARK: Clock → Notification Center (#410)

    func testClockReplayIsAnUnmodifiedSingleClickAtTheClock() throws {
        let point = CGPoint(x: 1900, y: 12)
        let events = try XCTUnwrap(SystemMenuBarClock.clickEvents(at: point))
        XCTAssertEqual(events.map(\.type), [.leftMouseDown, .leftMouseUp])
        for event in events {
            XCTAssertEqual(event.location, point)
            XCTAssertEqual(event.flags, [])
            XCTAssertEqual(event.getIntegerValueField(.mouseEventClickState), 1)
        }
    }

    func testClockIsWatchedOnlyWhileARestrictionIsHeld() {
        let engine = makeEngine()
        XCTAssertNil(clock.onClick)

        engine.collapse { _ in }
        XCTAssertNil(clock.onClick, "nothing is restricted until the activation lands")
        visibility.succeed(0)
        XCTAssertNotNil(clock.onClick)

        engine.expand()
        XCTAssertNil(clock.onClick, "an unrestricted clock opens Notification Center by itself")
    }

    // A clock engine: session steps and the lift watchdog run on the test's clock.
    private func makeClockEngine() -> NativeVisibilityEngine {
        let engine = makeEngine()
        engine.clockNow = { [unowned self] in time.now }
        engine.scheduleClockStep = { [unowned self] in time.after($0, $1) }
        engine.scheduleRestoreWatchdog = { _, _ in }
        engine.expandBar = { [unowned self, unowned engine] in expands += 1; engine.expand() }
        engine.collapseBar = { [unowned self, unowned engine] in collapses += 1; engine.collapse { _ in } }
        return engine
    }

    private func collapsedClockEngine() -> (NativeVisibilityEngine, FakeAssertion) {
        let engine = makeClockEngine()
        engine.collapse { _ in }
        return (engine, visibility.succeed(0))
    }

    func testClockClickWhileCollapsedExpandsTheBarAndPressesWithoutLifting() {
        let (engine, collapsed) = collapsedClockEngine()
        let location = CGPoint(x: 1950, y: 12)
        clock.click(at: location)

        XCTAssertEqual(expands, 1, "expanded the way a click on the arrow does")
        XCTAssertEqual(engine.state, .expanded)
        XCTAssertTrue(collapsed.isInvalidated)
        XCTAssertNil(clock.onClick, "an unrestricted clock closes the panel by itself")
        XCTAssertEqual(clock.presses.count, 1)
        XCTAssertEqual(clock.presses.first?.location, location)
        clock.presses[0].completion()
        XCTAssertEqual(visibility.requests.count, 1, "no restriction comes back while Notification Center is open")
        XCTAssertTrue(engine.defersAutoCollapse)
    }

    func testBarCollapsesOnceThePanelClosesAndStopsChecking() {
        let (engine, _) = collapsedClockEngine()
        clock.click()
        clock.panelOpen = true
        clock.presses[0].finished(.panelShown)
        time.advance(to: 5)
        XCTAssertEqual(collapses, 0)
        XCTAssertTrue(engine.defersAutoCollapse, "auto-collapse waits while the panel is open")
        let checks = clock.panelChecks
        XCTAssertEqual(checks, 51, accuracy: 1, "about one check every 0.1 s")

        clock.panelOpen = false
        time.advance(to: 5.1)
        XCTAssertEqual(collapses, 1)
        XCTAssertEqual(visibility.requests.count, 2)
        XCTAssertEqual(visibility.requests[1].bundles, visibility.requests[0].bundles)
        visibility.succeed(1)
        XCTAssertEqual(engine.state, .collapsed)
        XCTAssertFalse(engine.defersAutoCollapse)
        let checksAtCollapse = clock.panelChecks
        time.advance(to: 100)
        XCTAssertEqual(clock.panelChecks, checksAtCollapse, "nothing is checked after the collapse")
        XCTAssertNotNil(clock.onClick, "the next click is handled the same way")
    }

    func testClockClickOnABarTheUserExpandedNeverCollapsesIt() {
        let engine = makeClockEngine()
        engine.updateAlwaysHiddenSection(enabled: true, separatorHidden: true)
        let expanded = visibility.succeed(visibility.requests.count - 1)

        clock.click()
        XCTAssertEqual(expands, 0)
        XCTAssertTrue(expanded.isInvalidated, "the always-hidden section's restriction still blocks the clock")
        clock.presses[0].completion()
        XCTAssertEqual(visibility.requests.last?.bundles, ["com.dwarvesv.minimalbar", "com.hidden", "com.visible"])
        visibility.succeed(visibility.requests.count - 1)
        clock.panelOpen = true
        clock.presses[0].finished(.panelShown)
        time.advance(to: 3)
        clock.panelOpen = false
        time.advance(to: 4)
        XCTAssertEqual(collapses, 0)
        XCTAssertEqual(engine.state, .expanded)
        XCTAssertFalse(engine.defersAutoCollapse)
    }

    func testManualToggleWhileThePanelIsOpenKeepsTheBarAsTheUserLeftIt() {
        let (engine, _) = collapsedClockEngine()
        clock.click()
        clock.panelOpen = true
        clock.presses[0].finished(.panelShown)
        time.advance(to: 2)
        engine.userChangedBar()
        time.advance(to: 4)
        XCTAssertTrue(engine.defersAutoCollapse, "still open")
        clock.panelOpen = false
        time.advance(to: 5)
        XCTAssertEqual(collapses, 0)
        XCTAssertFalse(engine.defersAutoCollapse)
    }

    func testClockPressThatOpenedNothingIsRetriedOnceThenTheBarCollapses() {
        let (engine, _) = collapsedClockEngine()
        clock.click()
        XCTAssertEqual(clock.presses[0].mode, .restoreAfterPress)
        clock.presses[0].finished(.noPanel)
        XCTAssertEqual(clock.presses.count, 2, "a press that opened nothing is retried")
        XCTAssertEqual(clock.presses[1].mode, .restoreWhenPanelShows)
        clock.presses[1].finished(.noPanel)
        XCTAssertEqual(clock.presses.count, 2, "only once")
        XCTAssertEqual(collapses, 1, "nothing opened, so the bar goes back")
        visibility.succeed(1)
        XCTAssertEqual(engine.state, .collapsed)
    }

    func testClockPressThatOpensThePanelIsNotRetried() {
        let (engine, _) = collapsedClockEngine()
        clock.click()
        clock.panelOpen = true
        clock.presses[0].finished(.panelShown)
        time.advance(to: 1)
        XCTAssertEqual(clock.presses.count, 1)
        XCTAssertTrue(engine.defersAutoCollapse)
    }

    // With the always-hidden section hidden, expanding swaps one restriction for
    // another. The press waits for that swap, then lifts the new one.
    func testPressWaitsForTheExpandToLandWhenTheAlwaysHiddenSectionStaysHidden() {
        let engine = makeClockEngine()
        engine.updateAlwaysHiddenSection(enabled: true, separatorHidden: true)
        visibility.succeed(visibility.requests.count - 1)
        engine.collapse { _ in }
        let collapsed = visibility.succeed(visibility.requests.count - 1)
        XCTAssertEqual(engine.state, .collapsed)

        clock.click()
        XCTAssertEqual(expands, 1)
        XCTAssertTrue(clock.presses.isEmpty, "lifting now would cancel the expand in flight")
        XCTAssertFalse(collapsed.isInvalidated)
        let expanded = visibility.succeed(visibility.requests.count - 1)
        time.advance(to: 0.1)
        XCTAssertEqual(clock.presses.count, 1)
        XCTAssertTrue(expanded.isInvalidated, "lifted for the press")
        clock.presses[0].completion()
        XCTAssertEqual(visibility.requests.last?.bundles, ["com.dwarvesv.minimalbar", "com.hidden", "com.visible"])
    }

    func testFailedClockRestoreLeavesTheEngineExpanded() {
        let engine = makeClockEngine()
        engine.updateAlwaysHiddenSection(enabled: true, separatorHidden: true)
        visibility.succeed(visibility.requests.count - 1)
        clock.click()
        clock.presses[0].completion()
        visibility.fail(visibility.requests.count - 1)
        XCTAssertEqual(engine.state, .expanded)
        XCTAssertNil(clock.onClick)
    }

    func testCollapseDuringALiftKeepsTheRestrictionTheUserAskedFor() {
        let engine = makeClockEngine()
        engine.updateAlwaysHiddenSection(enabled: true, separatorHidden: true)
        visibility.succeed(visibility.requests.count - 1)
        clock.click()
        let before = visibility.requests.count
        engine.collapse { _ in }
        clock.presses[0].completion()
        XCTAssertEqual(visibility.requests.count, before + 1, "only the collapse activates; the lift's restore stands down")
    }

    func testWatchdogRestoresTheRestrictionWhenThePressNeverReports() {
        let engine = makeClockEngine()
        var watchdog: (delay: TimeInterval, fire: () -> Void)?
        engine.scheduleRestoreWatchdog = { watchdog = ($0, $1) }
        engine.updateAlwaysHiddenSection(enabled: true, separatorHidden: true)
        visibility.succeed(visibility.requests.count - 1)
        let before = visibility.requests.count

        clock.click()
        XCTAssertEqual(visibility.requests.count, before)
        XCTAssertEqual(try XCTUnwrap(watchdog).delay, NativeVisibilityEngine.clockLiftHardCap)
        watchdog?.fire()
        XCTAssertEqual(visibility.requests.count, before + 1, "the restriction comes back without the press")
        clock.presses[0].completion()
        XCTAssertEqual(visibility.requests.count, before + 1, "and only once")
    }

    func testNoWatchdogWhenNothingIsLifted() {
        let engine = makeClockEngine()
        var watchdogs = 0
        engine.scheduleRestoreWatchdog = { _, _ in watchdogs += 1 }
        engine.collapse { _ in }
        visibility.succeed(0)
        clock.click()
        XCTAssertEqual(clock.presses.count, 1)
        XCTAssertEqual(watchdogs, 0)
    }

    func testClockClickDuringAnActivationLeavesItAlone() {
        let engine = makeEngine()
        engine.updateAlwaysHiddenSection(enabled: true, separatorHidden: true)
        let expanded = visibility.succeed(visibility.requests.count - 1)
        var results: [CollapseResult] = []
        engine.collapse { results.append($0) }

        // Lifting the held assertion now would cancel the collapse in flight, and
        // a cancelled collapse never reports back.
        clock.click()
        XCTAssertTrue(clock.presses.isEmpty)
        XCTAssertFalse(expanded.isInvalidated)

        visibility.succeed(visibility.requests.count - 1)
        XCTAssertEqual(results, [.collapsed])
        XCTAssertEqual(engine.state, .collapsed)
    }

    // MARK: Microphone and camera (#432, #437)

    // Stands in for the controller: its expand for capture, and the auto-hide
    // timer every expand arms, on the manual clock.
    private func expandingLikeTheController(_ engine: NativeVisibilityEngine, autoHideAfter delay: TimeInterval = 10) {
        engine.expandBarForCapture = { [unowned self, unowned engine] in
            expands += 1
            engine.expand()
            time.after(delay) { [unowned engine] in engine.collapse { _ in } }
        }
    }

    private func collapsed(_ engine: NativeVisibilityEngine) -> FakeAssertion {
        engine.collapse { _ in }
        return visibility.succeed(visibility.requests.count - 1)
    }

    // Dictation tools keep the microphone open all day: capture running at
    // launch is not a start, and must never keep the bar from hiding.
    func testCaptureRunningAtLaunchDoesNotExpandAndCollapseStillHides() {
        capture.isActive = true
        let engine = makeEngine()
        expandingLikeTheController(engine)
        var results: [CollapseResult] = []
        engine.collapse { results.append($0) }

        XCTAssertEqual(visibility.requests.count, 1, "a restriction is requested while capturing")
        let held = visibility.succeed(0)
        XCTAssertEqual(results, [.collapsed])
        XCTAssertEqual(engine.state, .collapsed)
        XCTAssertFalse(held.isInvalidated)
        XCTAssertEqual(expands, 0)

        capture.set(true) // a device list change while the same capture continues
        XCTAssertEqual(expands, 0)
        XCTAssertFalse(held.isInvalidated)
    }

    func testCaptureStartingExpandsOnce() {
        let engine = makeEngine()
        expandingLikeTheController(engine)
        let held = collapsed(engine)

        capture.set(true)
        XCTAssertEqual(expands, 1, "expanded the way a click on the arrow does")
        XCTAssertEqual(engine.state, .expanded)
        XCTAssertTrue(held.isInvalidated, "the whole bar shows, recording indicator included")

        capture.set(true)
        XCTAssertEqual(expands, 1, "the same capture never expands again")
    }

    func testManualCollapseDuringCaptureStaysCollapsed() {
        let engine = makeEngine()
        expandingLikeTheController(engine)
        _ = collapsed(engine)
        capture.set(true)
        XCTAssertEqual(engine.state, .expanded)

        let held = collapsed(engine)
        XCTAssertEqual(engine.state, .collapsed)
        XCTAssertEqual(visibility.requests.last?.bundles, ["com.dwarvesv.minimalbar", "com.visible"])
        XCTAssertNotNil(clock.onClick, "a held restriction watches the clock as usual")

        capture.set(true)
        time.advance(to: 60)
        XCTAssertEqual(engine.state, .collapsed)
        XCTAssertFalse(held.isInvalidated)
        XCTAssertEqual(expands, 1)
    }

    func testAutoHideDuringCaptureCollapses() {
        let engine = makeEngine()
        expandingLikeTheController(engine, autoHideAfter: 10)
        _ = collapsed(engine)
        capture.set(true)
        XCTAssertEqual(engine.state, .expanded)
        let requestsBefore = visibility.requests.count

        time.advance(to: 10)
        XCTAssertEqual(engine.state, .calibrating, "the auto-hide collapse is not refused")
        XCTAssertEqual(visibility.requests.count, requestsBefore + 1)
        let held = visibility.succeed(visibility.requests.count - 1)
        XCTAssertEqual(engine.state, .collapsed)
        XCTAssertFalse(held.isInvalidated)
        XCTAssertTrue(capture.isActive)
        XCTAssertEqual(expands, 1)
    }

    func testCaptureStoppingThenStartingExpandsAgain() {
        let engine = makeEngine()
        expandingLikeTheController(engine)
        _ = collapsed(engine)
        capture.set(true)
        let held = collapsed(engine)

        capture.set(false)
        XCTAssertEqual(engine.state, .collapsed, "a stop changes nothing")
        XCTAssertFalse(held.isInvalidated)
        XCTAssertEqual(expands, 1)

        capture.set(true)
        XCTAssertEqual(expands, 2)
        XCTAssertEqual(engine.state, .expanded)
        XCTAssertTrue(held.isInvalidated)
    }

    func testCaptureStartingWithTheSettingOffNeverExpands() {
        let engine = makeEngine(expandsWhenCaptureStarts: false)
        expandingLikeTheController(engine)
        let held = collapsed(engine)

        capture.set(true)
        capture.set(false)
        capture.set(true)
        XCTAssertEqual(expands, 0)
        XCTAssertEqual(engine.state, .collapsed)
        XCTAssertFalse(held.isInvalidated)
        XCTAssertEqual(visibility.requests.count, 1)
    }

    // Expanded with the always-hidden section hidden still holds a restriction,
    // which would hide the recording indicator.
    func testCaptureStartingWhileExpandedShowsTheAlwaysHiddenSectionToo() {
        let engine = makeEngine()
        expandingLikeTheController(engine)
        engine.updateAlwaysHiddenSection(enabled: true, separatorHidden: true)
        let held = visibility.succeed(visibility.requests.count - 1)
        XCTAssertEqual(engine.state, .expanded)

        capture.set(true)
        XCTAssertEqual(expands, 0, "already expanded")
        XCTAssertTrue(held.isInvalidated)
        XCTAssertEqual(items.alwaysHiddenItem?.isVisible, true)
    }

    // A collapse in flight is left to land; it does not count as expanding.
    func testCaptureStartingDuringActivationLetsTheCollapseLand() {
        let engine = makeEngine()
        expandingLikeTheController(engine)
        var results: [CollapseResult] = []
        engine.collapse { results.append($0) }

        capture.set(true)
        let held = visibility.succeed(0)

        XCTAssertFalse(held.isInvalidated)
        XCTAssertEqual(results, [.collapsed])
        XCTAssertEqual(engine.state, .collapsed)
        XCTAssertEqual(expands, 0)
    }

    func testUnchangedCaptureStateLeavesTheRestrictionAlone() {
        let engine = makeEngine()
        engine.collapse { _ in }
        let collapsed = visibility.succeed(0)

        capture.set(false)
        XCTAssertFalse(collapsed.isInvalidated)
        XCTAssertEqual(visibility.requests.count, 1)
    }
}

// MARK: - Apps that start while something is hidden (K8)

final class AppsLaunchedWhileHidingTests: XCTestCase {
    private let own = "com.dwarvesv.minimalbar"
    private var items: FakeItems!
    private var inventory: FakeInventory!
    private var visibility: FakeVisibility!
    private var memory: InMemorySectionMemory!

    override func setUp() {
        super.setUp()
        items = FakeItems()
        inventory = FakeInventory()
        inventory.items = [item("com.always", x: 900), item("com.hidden", x: 1100), item("com.visible", x: 1400)]
        visibility = FakeVisibility()
        memory = InMemorySectionMemory()
    }

    private func makeEngine() -> NativeVisibilityEngine {
        let items = self.items!
        return NativeVisibilityEngine(items: items, inventory: inventory, visibility: visibility, clock: FakeClock(),
                                      ownBundleIdentifier: own,
                                      itemFrame: { $0 === items.toggleItem ? separator : alwaysHiddenSeparator },
                                      displays: { [mainDisplay] },
                                      isLTR: { true },
                                      sectionMemory: memory)
    }

    private func collapsed(_ engine: NativeVisibilityEngine) -> FakeAssertion {
        engine.collapse { _ in }
        return visibility.succeed(visibility.requests.count - 1)
    }

    func testAnAppNeverReadIsShownUntilTheNextReadPlacesIt() {
        let engine = makeEngine()
        let first = collapsed(engine)

        engine.applicationLaunched("com.new")
        XCTAssertEqual(visibility.requests.count, 2)
        guard visibility.requests.count == 2 else { return }
        XCTAssertEqual(visibility.requests[1].bundles, [own, "com.new", "com.visible"])
        XCTAssertFalse(first.isInvalidated, "the old restriction stays until the new one is active")
        visibility.succeed(1)
        XCTAssertTrue(first.isInvalidated)
        XCTAssertEqual(engine.state, .collapsed)

        // macOS put the new icon on the hidden side: the next read decides.
        engine.expand()
        inventory.items.append(item("com.new", x: 1150))
        _ = collapsed(engine)
        XCTAssertEqual(visibility.requests.last?.bundles, [own, "com.visible"])
    }

    func testAnAppQuitAtTheReadReturnsToTheSectionItWasLastReadIn() {
        let engine = makeEngine()
        _ = collapsed(engine)
        engine.expand()

        inventory.items = [item("com.always", x: 900)]
        _ = collapsed(engine)
        XCTAssertEqual(visibility.requests.last?.bundles, [own])

        engine.applicationLaunched("com.hidden")
        engine.applicationLaunched("com.always")
        XCTAssertEqual(visibility.requests.count, 2, "hidden apps stay hidden")

        engine.applicationLaunched("com.visible")
        XCTAssertEqual(visibility.requests.last?.bundles, [own, "com.visible"])
    }

    func testRememberedSectionsOutliveTheEngine() {
        _ = collapsed(makeEngine())

        // Hidden Bar starts again (a login) before the other apps do.
        visibility = FakeVisibility()
        inventory.items = []
        let engine = makeEngine()
        _ = collapsed(engine)
        engine.applicationLaunched("com.hidden")
        XCTAssertEqual(visibility.requests.count, 1)
        engine.applicationLaunched("com.visible")
        XCTAssertEqual(visibility.requests.last?.bundles, [own, "com.visible"])
    }

    func testAReadWinsOverTheRememberedSection() {
        memory.sections = ["com.visible": .hidden, "com.hidden": .visible]
        let engine = makeEngine()
        _ = collapsed(engine)
        XCTAssertEqual(visibility.requests[0].bundles, [own, "com.visible"])
        XCTAssertEqual(memory.sections["com.hidden"], .hidden)
    }

    func testAnAppRelaunchedSinceTheReadKeepsItsReadSection() {
        let engine = makeEngine()
        _ = collapsed(engine)
        engine.applicationLaunched("com.hidden")
        engine.applicationLaunched("com.visible")
        XCTAssertEqual(visibility.requests.count, 1)
    }

    func testALaunchDuringACollapseIsAllowedOnceItLands() {
        let engine = makeEngine()
        var results: [CollapseResult] = []
        engine.collapse { results.append($0) }
        engine.applicationLaunched("com.new")
        XCTAssertEqual(visibility.requests.count, 1, "nothing is swapped while an activation is in flight")

        visibility.succeed(0)
        XCTAssertEqual(results, [.collapsed])
        XCTAssertEqual(visibility.requests.count, 2)
        XCTAssertEqual(visibility.requests.last?.bundles, [own, "com.new", "com.visible"])
    }

    func testALaunchBeforeTheReadIsShownIfItsIconIsNotListedYet() {
        let engine = makeEngine()
        engine.applicationLaunched("com.slow")
        XCTAssertTrue(visibility.requests.isEmpty, "nothing is hidden yet")
        _ = collapsed(engine)
        XCTAssertEqual(visibility.requests[0].bundles, [own, "com.slow", "com.visible"])
        XCTAssertNil(memory.sections["com.slow"], "only reads are remembered")

        engine.applicationTerminated("com.slow")
        engine.expand()
        _ = collapsed(engine)
        XCTAssertEqual(visibility.requests.last?.bundles, [own, "com.visible"])
    }

    func testExpandedWithTheAlwaysHiddenSectionHiddenShowsTheHiddenSectionToo() {
        memory.sections = ["com.always2": .alwaysHidden]
        let engine = makeEngine()
        engine.updateAlwaysHiddenSection(enabled: true, separatorHidden: true)
        visibility.succeed(visibility.requests.count - 1)

        engine.applicationLaunched("com.always2")
        XCTAssertEqual(visibility.requests.count, 1)
        engine.applicationLaunched("com.new")
        XCTAssertEqual(visibility.requests.last?.bundles, [own, "com.hidden", "com.new", "com.visible"])
    }

    func testNothingIsSwappedWhileNothingIsHidden() {
        let engine = makeEngine()
        engine.applicationLaunched("com.new")
        _ = collapsed(engine)
        engine.expand()
        engine.applicationLaunched("com.other")
        XCTAssertEqual(visibility.requests.count, 1)
    }

    // Beta off: agent apps (no Dock icon, most menu-bar apps) are reported too,
    // so one that starts while collapsed is shown, as 1.11.2 meant to.
    func testWithPinnedSectionsOffAgentStartsAreStillReported() {
        XCTAssertTrue(AgentLaunchNotifications.isActive(pinnedSectionsEnabled: false))
        XCTAssertTrue(AgentLaunchNotifications.isActive(pinnedSectionsEnabled: true))

        let agents = NotificationCenter()
        let items = self.items!
        let engine = NativeVisibilityEngine(items: items, inventory: inventory, visibility: visibility, clock: FakeClock(),
                                            ownBundleIdentifier: own,
                                            itemFrame: { $0 === items.toggleItem ? separator : alwaysHiddenSeparator },
                                            displays: { [mainDisplay] }, isLTR: { true },
                                            sectionMemory: memory, agentLaunches: agents)
        _ = collapsed(engine)
        let app = try! XCTUnwrap(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first)
        agents.post(name: NSWorkspace.didLaunchApplicationNotification, object: nil,
                    userInfo: [NSWorkspace.applicationUserInfoKey: app])
        let delivered = expectation(description: "delivered on the main queue")
        DispatchQueue.main.async { delivered.fulfill() }
        wait(for: [delivered], timeout: 2)
        XCTAssertEqual(visibility.requests.last?.bundles, [own, "com.apple.dock", "com.visible"])
    }

    func testHiddenBarAndMacOSItemOwnersAreLeftAlone() {
        let engine = makeEngine()
        _ = collapsed(engine)
        engine.applicationLaunched(own)
        engine.applicationLaunched("com.apple.MenuBarAgent")
        engine.applicationLaunched("com.apple.controlcenter")
        XCTAssertEqual(visibility.requests.count, 1)
    }

    func testAFailedSwapFailsOpen() {
        let engine = makeEngine()
        _ = collapsed(engine)
        engine.applicationLaunched("com.new")
        XCTAssertEqual(visibility.requests.count, 2)
        guard visibility.requests.count == 2 else { return }
        visibility.fail(1)
        XCTAssertEqual(engine.state, .expanded)
    }

    func testUserDefaultsMemoryRoundTrips() throws {
        let suite = "HiddenBarTests.sectionMemory.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        UserDefaultsSectionMemory(defaults: defaults).sections = ["com.a": .hidden, "com.b": .visible, "com.c": .alwaysHidden]
        XCTAssertEqual(UserDefaultsSectionMemory(defaults: defaults).sections,
                       ["com.a": .hidden, "com.b": .visible, "com.c": .alwaysHidden])
    }
}

// MARK: - Pinned sections (#366, beta)

final class PinnedSectionsTests: XCTestCase {
    private let own = "com.dwarvesv.minimalbar"
    private var items: FakeItems!
    private var inventory: FakeInventory!
    private var visibility: FakeVisibility!
    private var observed: InMemorySectionMemory!
    private var table: InMemorySectionMemory!
    private var pins = true

    override func setUp() {
        super.setUp()
        items = FakeItems()
        inventory = FakeInventory()
        inventory.items = [item("com.always", x: 900), item("com.hidden", x: 1100), item("com.visible", x: 1400)]
        visibility = FakeVisibility()
        observed = InMemorySectionMemory()
        table = InMemorySectionMemory()
        pins = true
    }

    private func makeEngine() -> NativeVisibilityEngine {
        let items = self.items!
        return NativeVisibilityEngine(items: items, inventory: inventory, visibility: visibility, clock: FakeClock(),
                                      ownBundleIdentifier: own,
                                      itemFrame: { $0 === items.toggleItem ? separator : alwaysHiddenSeparator },
                                      displays: { [mainDisplay] },
                                      isLTR: { true },
                                      sectionMemory: observed,
                                      pinnedSections: table,
                                      pinsSections: { [unowned self] in pins })
    }

    @discardableResult
    private func collapse(_ engine: NativeVisibilityEngine) -> [String] {
        engine.collapse { _ in }
        visibility.succeed(visibility.requests.count - 1)
        return visibility.requests.last?.bundles ?? []
    }

    private func move(_ bundle: String, to x: CGFloat) {
        inventory.items = inventory.items.filter { $0.bundleIdentifier != bundle } + [item(bundle, x: x)]
    }

    // Given an app the user keeps visible
    // When it relaunches while the bar is collapsed and macOS puts its icon far left
    // Then the next collapse keeps it visible and the table is unchanged
    func testARelaunchedAppKeepsItsSectionWhereverMacOSPutsItsIcon() {
        let engine = makeEngine()
        XCTAssertEqual(collapse(engine), [own, "com.visible"])
        engine.applicationLaunched("com.visible")
        engine.expand()
        move("com.visible", to: 1150)
        XCTAssertEqual(collapse(engine), [own, "com.visible"])
        XCTAssertEqual(table.sections["com.visible"], .visible)
        XCTAssertEqual(engine.state, .collapsed)

        // Later collapses with the icon still there keep it visible too.
        engine.expand()
        XCTAssertEqual(collapse(engine), [own, "com.visible"])
    }

    // Without the beta, the same relaunch hides the app (v1.11.2, the drift #366 is about).
    func testWithTheBetaOffARelaunchedAppGoesWhereMacOSPutsIt() {
        pins = false
        table.sections = ["com.visible": .visible]
        let engine = makeEngine()
        XCTAssertEqual(collapse(engine), [own, "com.visible"])
        engine.applicationLaunched("com.visible")
        engine.expand()
        move("com.visible", to: 1150)
        XCTAssertEqual(collapse(engine), [own])
        XCTAssertEqual(table.sections, ["com.visible": .visible], "the table is not touched while the beta is off")
        XCTAssertEqual(observed.sections["com.visible"], .hidden)
    }

    func testADragOfAnAppThatDidNotRelaunchEditsTheTable() {
        let engine = makeEngine()
        collapse(engine)
        engine.expand()
        move("com.hidden", to: 1450)
        XCTAssertEqual(collapse(engine), [own, "com.hidden", "com.visible"])
        XCTAssertEqual(table.sections["com.hidden"], .visible)

        engine.expand()
        move("com.visible", to: 1120)
        XCTAssertEqual(collapse(engine), [own, "com.hidden"])
        XCTAssertEqual(table.sections["com.visible"], .hidden)
    }

    // Given an app Hidden Bar has never seen
    // When it starts and macOS puts its icon on the hidden side
    // Then it is shown, and stays shown on later reads of the same position
    func testANeverSeenAppStartsVisibleAndStaysVisible() {
        let engine = makeEngine()
        collapse(engine)
        engine.applicationLaunched("com.new")
        XCTAssertEqual(visibility.requests.last?.bundles, [own, "com.new", "com.visible"], "shown at once")
        visibility.succeed(visibility.requests.count - 1)
        XCTAssertNil(table.sections["com.new"], "an app without an icon in a read is not added")

        engine.expand()
        inventory.items.append(item("com.new", x: 1150))
        XCTAssertEqual(collapse(engine), [own, "com.new", "com.visible"])
        XCTAssertEqual(table.sections["com.new"], .visible)

        engine.expand()
        XCTAssertEqual(collapse(engine), [own, "com.new", "com.visible"], "an unchanged position is not a drag")
    }

    func testAppsAlreadyRunningWithNoTableEntryTakeTheirPosition() {
        let engine = makeEngine()
        XCTAssertEqual(collapse(engine), [own, "com.visible"])
        XCTAssertEqual(table.sections, ["com.always": .hidden, "com.hidden": .hidden, "com.visible": .visible])
    }

    // A Preferences edit is not undone by the next read, though the icon did not move.
    func testAPreferencesEditOutlivesTheNextRead() {
        let engine = makeEngine()
        collapse(engine)
        PinnedSectionEdits.set(.hidden, for: "com.visible", in: table)
        engine.pinnedSectionsDidChange()
        XCTAssertEqual(visibility.requests.last?.bundles, [own], "applied at once")
        visibility.succeed(visibility.requests.count - 1)

        engine.expand()
        XCTAssertEqual(collapse(engine), [own])
        XCTAssertEqual(table.sections["com.visible"], .hidden)
    }

    func testResetAllToVisibleShowsEveryAppWithoutARelaunch() {
        table.sections = ["com.always": .alwaysHidden, "com.hidden": .hidden, "com.visible": .visible, "com.gone": .hidden]
        let engine = makeEngine()
        XCTAssertEqual(collapse(engine), [own, "com.visible"])
        PinnedSectionEdits.resetAllToVisible(in: table)
        engine.pinnedSectionsDidChange()
        XCTAssertEqual(visibility.requests.last?.bundles, [own, "com.always", "com.hidden", "com.visible"])
        visibility.succeed(visibility.requests.count - 1)
        XCTAssertEqual(engine.state, .collapsed)
        XCTAssertEqual(Set(table.sections.values), [.visible])
        XCTAssertEqual(table.sections.count, 4, "apps not running are reset too")
    }

    func testAnAppThatStartsWhileHidingGetsItsPinnedSection() {
        table.sections = ["com.later": .visible, "com.later-hidden": .hidden]
        observed.sections = ["com.later": .hidden]
        let engine = makeEngine()
        collapse(engine)
        engine.applicationLaunched("com.later-hidden")
        XCTAssertEqual(visibility.requests.count, 1, "kept hidden")
        engine.applicationLaunched("com.later")
        XCTAssertEqual(visibility.requests.last?.bundles, [own, "com.later", "com.visible"], "the table wins over the last read")
    }

    func testEditsAreIgnoredWhileTheBetaIsOff() {
        pins = false
        let engine = makeEngine()
        collapse(engine)
        table.sections["com.visible"] = .hidden
        engine.pinnedSectionsDidChange()
        XCTAssertEqual(visibility.requests.count, 1)
    }

    func testTheTableStartsFromTheLastReadSections() throws {
        let suite = "HiddenBarTests.pinnedSections.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        UserDefaultsSectionMemory(defaults: defaults).sections = ["com.a": .hidden, "com.b": .alwaysHidden]
        let pinned = UserDefaultsPinnedSections(defaults: defaults)
        XCTAssertEqual(pinned.sections, ["com.a": .hidden, "com.b": .alwaysHidden])
        XCTAssertNil(defaults.object(forKey: UserDefaultsPinnedSections.key), "seeding writes nothing")

        pinned.sections["com.a"] = .visible
        UserDefaultsSectionMemory(defaults: defaults).sections = ["com.a": .alwaysHidden]
        XCTAssertEqual(UserDefaultsPinnedSections(defaults: defaults).sections, ["com.a": .visible, "com.b": .alwaysHidden],
                       "once written, the table no longer follows the reads")
    }

    // #224 on 27: given an app set always-hidden in Preferences, with no
    // always-hidden separator, when the bar expands, then it stays hidden.
    func testAnAlwaysHiddenAppStaysHiddenWhileExpandedWithoutTheSeparator() {
        table.sections = ["com.hidden": .alwaysHidden]
        let engine = makeEngine()
        XCTAssertTrue(engine.separatorsHiddenForCollapse(current: false), "every collapse hides the section again")
        engine.updateAlwaysHiddenSection(enabled: false, separatorHidden: true)
        XCTAssertEqual(collapse(engine), [own, "com.visible"])

        engine.expand()
        XCTAssertEqual(visibility.requests.last?.bundles, [own, "com.always", "com.visible"])
        visibility.succeed(visibility.requests.count - 1)
        XCTAssertEqual(engine.state, .expanded)
        XCTAssertFalse(items.alwaysHiddenItem?.isVisible ?? true)
    }

    // Without the beta: v1.11.2 reveals everything on expand unless the
    // always-hidden separator is enabled and hidden.
    func testWithTheBetaOffAnExpandWithoutTheSeparatorRevealsEverything() {
        pins = false
        table.sections = ["com.hidden": .alwaysHidden]
        let engine = makeEngine()
        XCTAssertFalse(engine.separatorsHiddenForCollapse(current: false))
        XCTAssertTrue(engine.separatorsHiddenForCollapse(current: true))
        engine.updateAlwaysHiddenSection(enabled: false, separatorHidden: true)
        XCTAssertTrue(visibility.requests.isEmpty)
        engine.collapse { _ in }
        let collapsed = visibility.succeed(visibility.requests.count - 1)
        let count = visibility.requests.count
        engine.expand()
        XCTAssertEqual(visibility.requests.count, count, "no restriction while expanded")
        XCTAssertTrue(collapsed.isInvalidated)
    }

    // Option-click shows the section until the next collapse; that collapse
    // hides it again from a fresh read, so ⌘-drags made meanwhile count.
    func testOptionClickRevealsTheSectionUntilTheNextCollapse() {
        table.sections = ["com.hidden": .alwaysHidden]
        let engine = makeEngine()
        engine.updateAlwaysHiddenSection(enabled: true, separatorHidden: true)
        collapse(engine)
        engine.expand()
        let held = visibility.succeed(visibility.requests.count - 1)

        engine.updateAlwaysHiddenSection(enabled: true, separatorHidden: false)
        XCTAssertTrue(held.isInvalidated, "everything shows")
        XCTAssertTrue(items.alwaysHiddenItem?.isVisible ?? false, "the separator shows to be dragged")

        move("com.always", to: 1450)
        let reads = inventory.snapshots
        engine.updateAlwaysHiddenSection(enabled: true, separatorHidden: true)
        XCTAssertGreaterThan(inventory.snapshots, reads, "read from the unrestricted bar")
        XCTAssertEqual(table.sections["com.always"], .visible)
        XCTAssertEqual(visibility.requests.last?.bundles, [own, "com.always", "com.visible"])
    }

    func testAPreferencesEditToAlwaysHiddenHidesItOnTheExpandedBarAtOnce() {
        let engine = makeEngine()
        engine.updateAlwaysHiddenSection(enabled: false, separatorHidden: true)
        collapse(engine)
        engine.expand()
        XCTAssertEqual(visibility.requests.count, 1, "nothing to keep hidden yet")

        PinnedSectionEdits.set(.alwaysHidden, for: "com.visible", in: table)
        engine.pinnedSectionsDidChange()
        XCTAssertEqual(visibility.requests.last?.bundles, [own, "com.always", "com.hidden"])
        visibility.succeed(visibility.requests.count - 1)

        PinnedSectionEdits.resetAllToVisible(in: table)
        engine.pinnedSectionsDidChange()
        XCTAssertEqual(visibility.requests.count, 2, "nothing left to hide: the restriction is dropped")
        XCTAssertEqual(engine.state, .expanded)
    }

    func testTheListShowsEveryTableAppByName() {
        let entries = PinnedSectionsList.entries(
            table: ["com.b": .hidden, "com.a": .visible, "com.gone": .alwaysHidden, "com.apple.controlcenter": .visible],
            name: { ["com.a": "zeta", "com.b": "Alpha"][$0] })
        XCTAssertEqual(entries.map(\.bundle), ["com.b", "com.gone", "com.apple.controlcenter", "com.a"])
        XCTAssertEqual(entries.map(\.section), [.hidden, .alwaysHidden, .visible, .visible])
        XCTAssertEqual(entries[1].name, "com.gone", "an uninstalled app is listed by bundle id")
    }

    // Most menu-bar apps are agents, whose starts NSWorkspace does not post.
    func testAgentStartsAndQuitsAreReportedAndDockAppsAreLeftToNSWorkspace() {
        let agent = { (name: String) in name.hasPrefix("agent") }
        let started = AgentLaunchNotifications.notifications(kind: .insertion, inserted: ["agent.a", "dock.b"], removed: [], isAgent: agent)
        XCTAssertEqual(started.map(\.0), [NSWorkspace.didLaunchApplicationNotification])
        XCTAssertEqual(started.map(\.1), ["agent.a"])
        let quit = AgentLaunchNotifications.notifications(kind: .removal, inserted: [], removed: ["dock.b", "agent.c"], isAgent: agent)
        XCTAssertEqual(quit.map(\.0), [NSWorkspace.didTerminateApplicationNotification])
        XCTAssertEqual(quit.map(\.1), ["agent.c"])
        XCTAssertTrue(AgentLaunchNotifications.notifications(kind: .setting, inserted: ["agent.a"], removed: [], isAgent: agent).isEmpty)
    }

    func testAnAgentStartReachesTheEngineThroughItsOwnCenter() {
        let agents = NotificationCenter()
        let items = self.items!
        let engine = NativeVisibilityEngine(items: items, inventory: inventory, visibility: visibility, clock: FakeClock(),
                                            ownBundleIdentifier: own,
                                            itemFrame: { $0 === items.toggleItem ? separator : alwaysHiddenSeparator },
                                            displays: { [mainDisplay] }, isLTR: { true },
                                            sectionMemory: observed, pinnedSections: table,
                                            pinsSections: { true }, agentLaunches: agents)
        collapse(engine)
        // Any running app with a bundle id stands in for the agent; the Dock always runs.
        let app = try! XCTUnwrap(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first)
        agents.post(name: NSWorkspace.didLaunchApplicationNotification, object: nil,
                    userInfo: [NSWorkspace.applicationUserInfoKey: app])
        let expectation = expectation(description: "delivered on the main queue")
        DispatchQueue.main.async { expectation.fulfill() }
        wait(for: [expectation], timeout: 2)
        XCTAssertEqual(visibility.requests.count, 2)
        XCTAssertEqual(visibility.requests.last?.bundles, [own, "com.apple.dock", "com.visible"])
    }

    func testResolverRules() {
        var observed: [String: MenuBarSection] = ["moved": .hidden, "still": .hidden, "relaunched": .visible]
        var table: [String: MenuBarSection] = ["moved": .hidden, "still": .visible, "relaunched": .visible]
        let resolved = PinnedSectionResolver.resolve(
            read: ["moved": .visible, "still": .hidden, "relaunched": .hidden, "new": .hidden, "running": .alwaysHidden],
            launchedSinceRead: ["relaunched", "new"], observed: &observed, table: &table)
        XCTAssertEqual(resolved, ["moved": .visible, "still": .visible, "relaunched": .visible, "new": .visible, "running": .alwaysHidden])
        XCTAssertEqual(table, resolved)
        XCTAssertEqual(observed, ["moved": .visible, "still": .hidden, "relaunched": .hidden, "new": .hidden, "running": .alwaysHidden])
    }
}

// MARK: - Legacy engine

// macOS 27 hides the allowed icons of an app it does not know by bundle id
// (one run from outside an Applications folder), Hidden Bar's own arrow
// included. Nothing may be hidden then, or no arrow is left to expand with.
final class ApplicationsFolderTests: XCTestCase {
    private var items: FakeItems!
    private var inventory: FakeInventory!
    private var visibility: FakeVisibility!

    override func setUp() {
        super.setUp()
        items = FakeItems()
        inventory = FakeInventory()
        inventory.items = [item("com.always", x: 900), item("com.hidden", x: 1100), item("com.visible", x: 1400)]
        visibility = FakeVisibility()
    }

    private func makeEngine(inApplications: Bool) -> NativeVisibilityEngine {
        let items = self.items!
        return NativeVisibilityEngine(items: items, inventory: inventory, visibility: visibility,
                                      ownBundleIdentifier: "com.dwarvesv.minimalbar",
                                      itemFrame: { $0 === items.toggleItem ? separator : alwaysHiddenSeparator },
                                      displays: { [mainDisplay] },
                                      isLTR: { true },
                                      runsFromApplicationsFolder: { inApplications })
    }

    func testOutsideApplicationsFolderNothingIsHidden() {
        let engine = makeEngine(inApplications: false)
        var result: CollapseResult?
        engine.collapse { result = $0 }

        XCTAssertEqual(result, .unavailable)
        XCTAssertEqual(engine.state, .unavailable)
        XCTAssertTrue(visibility.requests.isEmpty, "a restriction would hide the arrow")
    }

    func testOutsideApplicationsFolderAlwaysHiddenSectionStaysShown() {
        let engine = makeEngine(inApplications: false)
        engine.updateAlwaysHiddenSection(enabled: true, separatorHidden: true)

        XCTAssertTrue(visibility.requests.isEmpty, "a restriction would hide the arrow")
        XCTAssertEqual(items.alwaysHiddenItem?.length, 20)
    }

    func testInApplicationsFolderHides() {
        let engine = makeEngine(inApplications: true)
        engine.collapse { _ in }
        XCTAssertEqual(visibility.requests.first?.bundles, ["com.dwarvesv.minimalbar", "com.visible"])
    }

    func testApplicationsFolderCheck() {
        let folders = [URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/Users/me/Applications")]
        func inside(_ path: String) -> Bool {
            NativeVisibilityEngine.isInApplicationsFolder(URL(fileURLWithPath: path), applicationFolders: folders)
        }
        XCTAssertTrue(inside("/Applications/Hidden Bar.app"))
        XCTAssertTrue(inside("/Applications/Setapp/Hidden Bar.app"))
        XCTAssertTrue(inside("/Users/me/Applications/Hidden Bar.app"))
        XCTAssertFalse(inside("/Users/me/Downloads/Hidden Bar.app"))
        XCTAssertFalse(inside("/private/var/folders/x/T/AppTranslocation/1234/d/Hidden Bar.app"), "translocated from Downloads")
        XCTAssertFalse(inside("/private/tmp/build/Debug-Direct/Hidden Bar.app"))
        XCTAssertFalse(inside("/ApplicationsOld/Hidden Bar.app"))
    }
}

final class LegacyLengthEngineTests: XCTestCase {
    func testUsesWidestScreenRegardlessOfDisplayOrder() {
        let configurations: [([CGFloat], CGFloat)] = [
            ([1200], 2400),
            ([800, 1600, 1200], 3200),
            ([2560, 1440, 3840, 1920], 7680)
        ]
        for (configuration, expected) in configurations {
            for widths in [configuration, Array(configuration.reversed())] {
                let items = FakeItems()
                let engine = LegacyLengthEngine(items: items, screenWidths: { widths })
                engine.collapse { _ in }
                XCTAssertEqual(items.separatorItem.length, expected)
            }
        }
    }

    // Expanding the ordinary section leaves the always-hidden spacer inflated;
    // a display change must resize it too, or a wider display shows its icons.
    func testDisplayChangesRefreshHiddenSectionsIndependently() {
        for collapsed in [false, true] {
            for alwaysHiddenEnabled in [false, true] {
                for separatorHidden in [false, true] {
                    let items = FakeItems()
                    var widths: [CGFloat] = [900]
                    let engine = LegacyLengthEngine(items: items, screenWidths: { widths })
                    engine.expand()
                    if collapsed { engine.collapse { _ in } }
                    engine.updateAlwaysHiddenSection(enabled: alwaysHiddenEnabled, separatorHidden: separatorHidden)

                    let transitions: [([CGFloat], CGFloat)] = [
                        ([900, 1800, 1200], 3600), // attach wider displays
                        ([900], 1800),             // detach them
                        ([], 3456),                // no display listed for a moment
                        ([6000], 10000)            // very wide logical display
                    ]
                    for (nextWidths, hiddenLength) in transitions {
                        widths = nextWidths
                        engine.invalidateLayout()
                        let context = "collapsed=\(collapsed), alwaysHidden=\(alwaysHiddenEnabled), separatorHidden=\(separatorHidden), screens=\(widths)"
                        XCTAssertEqual(items.separatorItem.length, collapsed ? hiddenLength : 20, context)
                        XCTAssertEqual(items.alwaysHiddenItem?.length,
                                       alwaysHiddenEnabled ? (separatorHidden ? hiddenLength : 20) : 0, context)
                        XCTAssertEqual(engine.state, collapsed ? .collapsed : .expanded, context)
                    }
                }
            }
        }
    }

    func testRotationAndScalingChangesUseLatestWidths() {
        let items = FakeItems()
        var widths: [CGFloat] = [2400, 1200]
        let engine = LegacyLengthEngine(items: items, screenWidths: { widths })
        engine.collapse { _ in }
        widths = [1350, 2000]
        engine.invalidateLayout()
        XCTAssertEqual(items.separatorItem.length, 4000)
        widths = [1600, 1000]
        engine.invalidateLayout()
        XCTAssertEqual(items.separatorItem.length, 3200)
    }

    func testMissingScreensAndExtremeWidthsStayBounded() {
        for (widths, expected): ([CGFloat], CGFloat) in [([], 3456), ([100], 500), ([8000], 10000)] {
            let items = FakeItems()
            let engine = LegacyLengthEngine(items: items, screenWidths: { widths })
            engine.collapse { _ in }
            XCTAssertEqual(items.separatorItem.length, expected)
        }
    }

    func testCollapseAndExpandFlipSeparatorLength() {
        let items = FakeItems()
        let engine = LegacyLengthEngine(items: items)
        XCTAssertEqual(engine.state, .expanded)

        var result: CollapseResult?
        engine.collapse { result = $0 }
        XCTAssertEqual(result, .collapsed)
        XCTAssertEqual(engine.state, .collapsed)
        XCTAssertEqual(items.alwaysHiddenItem?.length, 20, "collapse leaves the always-hidden item alone")

        engine.expand()
        XCTAssertEqual(engine.state, .expanded)
        XCTAssertEqual(items.separatorItem.length, 20)
    }
}

// MARK: - Legacy recovery patches (#224, #242)

final class LegacyRecoveryPatchTests: XCTestCase {
    // Given macOS 26 and the always-hidden section shown (the default after enabling it)
    // When the bar collapses
    // Then the collapse hides the section again, so the next expand keeps it hidden
    func testEveryCollapseHidesTheAlwaysHiddenSectionAgainUpToMacOS26() {
        for os in [13, 15, 26] {
            let engine = LegacyLengthEngine(items: FakeItems(), osMajorVersion: os)
            XCTAssertTrue(engine.separatorsHiddenForCollapse(current: false), "macOS \(os)")
            XCTAssertTrue(engine.separatorsHiddenForCollapse(current: true), "macOS \(os)")
        }
    }

    func testTheArrowMenuOffersShowEverythingUpToMacOS26() {
        XCTAssertTrue(LegacyLengthEngine(items: FakeItems(), osMajorVersion: 26).offersShowEverything)
        XCTAssertTrue(LegacyLengthEngine(items: FakeItems(), osMajorVersion: 13).offersShowEverything)
    }

    // The App Store build runs this engine on 27 too; nothing changes there.
    func testNothingChangesOnMacOS27() {
        let engine = LegacyLengthEngine(items: FakeItems(), osMajorVersion: 27)
        XCTAssertFalse(engine.separatorsHiddenForCollapse(current: false))
        XCTAssertTrue(engine.separatorsHiddenForCollapse(current: true))
        XCTAssertFalse(engine.offersShowEverything)
    }

    func testTheNativeEngineOffersNoShowEverything() {
        let native = NativeVisibilityEngine(items: FakeItems(), inventory: FakeInventory(), visibility: FakeVisibility(), clock: FakeClock())
        XCTAssertFalse(native.offersShowEverything)
        XCTAssertFalse(native.separatorsHiddenForCollapse(current: false), "beta off: unchanged")
    }

    // What the controller does on macOS 26 around a collapse, applied to the
    // engine: the section is shown (revealed), the collapse hides it again,
    // and the next expand keeps it hidden while the rest shows.
    func testARevealLastsOnlyUntilTheNextCollapse() {
        let items = FakeItems()
        let engine = LegacyLengthEngine(items: items, screenWidths: { [1000] }, osMajorVersion: 26)
        engine.updateAlwaysHiddenSection(enabled: true, separatorHidden: false)
        XCTAssertEqual(items.alwaysHiddenItem?.length, 20, "revealed")

        let separatorsHidden = engine.separatorsHiddenForCollapse(current: false)
        engine.updateAlwaysHiddenSection(enabled: true, separatorHidden: separatorsHidden)
        engine.collapse { _ in }
        engine.expand()
        XCTAssertEqual(items.separatorItem.length, 20, "the hidden section shows")
        XCTAssertEqual(items.alwaysHiddenItem?.length, 2000, "the always-hidden section stays hidden")
    }
}

// MARK: - Arrangement order (#336, PR #381)

final class MenuBarOrderTests: XCTestCase {
    // Given macOS 26 right after launch, every status item still at (0, 0)
    // When the controller checks that the separator sits on the arrow's hidden side
    // Then the check refuses, so the launch collapse cannot hide the arrow itself
    func testUnplacedItemsAreNotAValidArrangement() {
        for leftToRight in [true, false] {
            XCTAssertFalse(MenuBarOrder.isOrigin(.zero, onHiddenSideOf: .zero, leftToRight: leftToRight))
            XCTAssertFalse(MenuBarOrder.isOrigin(.zero, onHiddenSideOf: CGPoint(x: 1200, y: 1093), leftToRight: leftToRight))
            XCTAssertFalse(MenuBarOrder.isOrigin(CGPoint(x: 1200, y: 1093), onHiddenSideOf: .zero, leftToRight: leftToRight))
            XCTAssertFalse(MenuBarOrder.isOrigin(nil, onHiddenSideOf: CGPoint(x: 1200, y: 1093), leftToRight: leftToRight))
        }
        XCTAssertFalse(MenuBarOrder.isPlaced(CGPoint.zero))
        XCTAssertFalse(MenuBarOrder.isPlaced(nil as CGPoint?))
    }

    // The geometry #381 measured a second later on 26.5.2: a stale saved order put
    // the arrow (x -2991) left of the separator (x -2566), inside the hidden zone.
    func testArrowInsideTheHiddenZoneIsRefused() {
        let arrow = CGPoint(x: -2991, y: 1307)
        let separator = CGPoint(x: -2566, y: 1307)
        XCTAssertFalse(MenuBarOrder.isOrigin(separator, onHiddenSideOf: arrow, leftToRight: true))
        XCTAssertTrue(MenuBarOrder.isPlaced(arrow))
    }

    func testPlacedItemsKeepTheirOrderInBothDirections() {
        let left = CGPoint(x: 1300, y: 1093)
        let right = CGPoint(x: 1340, y: 1093)
        XCTAssertTrue(MenuBarOrder.isOrigin(left, onHiddenSideOf: right, leftToRight: true))
        XCTAssertFalse(MenuBarOrder.isOrigin(right, onHiddenSideOf: left, leftToRight: true))
        XCTAssertTrue(MenuBarOrder.isOrigin(right, onHiddenSideOf: left, leftToRight: false))
        XCTAssertFalse(MenuBarOrder.isOrigin(left, onHiddenSideOf: right, leftToRight: false))
        // A display left of the primary one has negative x; still placed.
        XCTAssertTrue(MenuBarOrder.isOrigin(CGPoint(x: -400, y: 1093), onHiddenSideOf: CGPoint(x: -360, y: 1093), leftToRight: true))
    }

    // Status items that macOS has not put in the menu bar have no position, so the
    // legacy engine reports the arrangement unknown and the launch collapse waits.
    func testLegacyArrangementIsUnknownUntilTheItemsArePlaced() {
        let items = FakeItems()
        let engine = LegacyLengthEngine(items: items)
        XCTAssertFalse(engine.isArrangementKnown)
        XCTAssertFalse(engine.isArrangementValid, "never valid while unknown")
        XCTAssertFalse(engine.isAlwaysHiddenSeparatorPlaced)
    }
}

// MARK: - Inventory retry

final class AccessibilityInventoryRetryTests: XCTestCase {
    private func item(_ bundle: String, x: CGFloat) -> MenuBarInventoryItem {
        return MenuBarInventoryItem(bundleIdentifier: bundle, frame: CGRect(x: x, y: 0, width: 20, height: 22))
    }

    func testAnAppThatTimesOutOnceIsReadAgainAndKept() {
        let lock = NSLock()
        var calls: [Int: [Float]] = [:]
        var unanswered: [Int] = []
        let items = AccessibilityMenuBarInventory.collect(count: 3, read: { index, timeout in
            lock.lock(); calls[index, default: []].append(timeout); let attempt = calls[index]!.count; lock.unlock()
            if index == 1 && attempt == 1 { return .timedOut }
            return .items([self.item("app\(index)", x: CGFloat(index) * 30)])
        }, unanswered: { index in
            unanswered.append(index)
            return []
        })
        XCTAssertEqual(items.map(\.bundleIdentifier), ["app0", "app1", "app2"], "running-app order kept")
        XCTAssertEqual(unanswered, [], "the re-read answered")
        XCTAssertEqual(calls[1]?.count, 2)
        XCTAssertGreaterThan(calls[1]?.last ?? 0, calls[1]?.first ?? 0, "the re-read gets more time")
        XCTAssertEqual(calls[0]?.count, 1)
        XCTAssertEqual(calls[2]?.count, 1)
    }

    func testTheRetryIsBoundedToOneRereadAndTheAppStaysVisible() {
        let lock = NSLock()
        var calls = 0
        var unanswered: [Int] = []
        let items = AccessibilityMenuBarInventory.collect(count: 3, read: { index, _ in
            if index != 1 { return .items([self.item("app\(index)", x: CGFloat(index) * 30)]) }
            lock.lock(); calls += 1; lock.unlock()
            return .timedOut
        }, unanswered: { index in
            unanswered.append(index)
            return [MenuBarInventoryItem(bundleIdentifier: "app\(index)", frame: .zero, isUnreadable: true)]
        })
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(unanswered, [1])
        XCTAssertEqual(items.map(\.bundleIdentifier), ["app0", "app1", "app2"],
                       "an app that never answers is kept, in running-app order")
        XCTAssertEqual(items.map(\.isUnreadable), [false, true, false])
    }

    func testNoRereadWhenEveryAppAnswers() {
        let lock = NSLock()
        var calls = 0
        _ = AccessibilityMenuBarInventory.collect(count: 4, read: { _, _ in
            lock.lock(); calls += 1; lock.unlock()
            return .items([])
        }, unanswered: { _ in
            XCTFail("every app answered")
            return []
        })
        XCTAssertEqual(calls, 4)
    }
}

// MARK: - Clock replay timing

// A manual clock: scheduled steps run only when the test advances time.
private final class ManualTime {
    private(set) var now: TimeInterval = 0
    private var pending: [(due: TimeInterval, step: () -> Void)] = []

    func after(_ delay: TimeInterval, _ step: @escaping () -> Void) {
        pending.append((now + delay, step))
    }

    func advance(to time: TimeInterval) {
        while let next = pending.enumerated().filter({ $0.element.due <= time }).min(by: { $0.element.due < $1.element.due }) {
            pending.remove(at: next.offset)
            now = max(now, next.element.due)
            next.element.step()
        }
        now = time
    }
}

final class ClockReplayTests: XCTestCase {
    private var time: ManualTime!
    private var panelOpensAt: TimeInterval = .infinity
    private var restoredAt: TimeInterval?
    private var outcome: (ClockPressOutcome, TimeInterval)?

    override func setUp() {
        super.setUp()
        time = ManualTime()
        panelOpensAt = .infinity
        restoredAt = nil
        outcome = nil
    }

    private func replay(_ mode: ClockPressMode, restoreAfterPress: TimeInterval = 0.04) -> ClockReplay {
        let replay = ClockReplay(timing: .init(restoreAfterPress: restoreAfterPress), mode: mode,
                                 now: { [unowned self] in time.now },
                                 after: { [unowned self] in time.after($0, $1) },
                                 panelIsOpen: { [unowned self] in time.now >= panelOpensAt },
                                 restore: { [unowned self] in
                                     XCTAssertNil(restoredAt, "restored once")
                                     restoredAt = time.now
                                 },
                                 finished: { [unowned self] in outcome = ($0, time.now) })
        replay.pressed()
        return replay
    }

    func testRestoresRightAfterThePressWithoutWaitingForThePanel() {
        panelOpensAt = 0.09
        let replay = replay(.restoreAfterPress)
        time.advance(to: 0.04)
        XCTAssertEqual(restoredAt, 0.04, "hidden icons show only until MenuBarAgent has the press")
        XCTAssertNil(outcome)
        time.advance(to: 1)
        XCTAssertEqual(outcome?.0, .panelShown)
        XCTAssertEqual(outcome?.1 ?? 0, 0.09, accuracy: 0.0051)
        _ = replay
    }

    func testASynchronousPressRestoresAtOnce() {
        _ = replay(.restoreAfterPress, restoreAfterPress: 0)
        XCTAssertEqual(restoredAt, 0)
    }

    func testFallbackRestoresWithinOnePollOfThePanelShowing() {
        panelOpensAt = 0.071
        _ = replay(.restoreWhenPanelShows)
        time.advance(to: 0.07)
        XCTAssertNil(restoredAt, "the fallback holds the lift until the panel shows")
        time.advance(to: 1)
        XCTAssertEqual(outcome?.0, .panelShown)
        XCTAssertEqual(restoredAt ?? 1, 0.071, accuracy: 0.0051)
    }

    func testNoPanelIsReportedAtTheTimeoutAndTheRestrictionIsBack() {
        _ = replay(.restoreWhenPanelShows)
        time.advance(to: 2)
        XCTAssertEqual(outcome?.0, .noPanel)
        XCTAssertEqual(outcome?.1 ?? 2, 0.3, accuracy: 0.0051)
        XCTAssertEqual(restoredAt ?? 2, 0.3, accuracy: 0.0051)
        XCTAssertLessThan(0.3 + 0.03 + 0.15, NativeVisibilityEngine.clockLiftHardCap,
                          "the fallback fits inside the watchdog's cap")
    }
}

// The clock-click state machine on its own, with a manual clock and a fake panel.
final class NotificationCenterSessionTests: XCTestCase {
    private var time: ManualTime!
    private var panelOpen = false
    private var panelChecks = 0
    private var busy = false
    private var presses: [(mode: ClockPressMode, finished: (ClockPressOutcome) -> Void)] = []
    // What the bar saw, in order: "expand", "press", "collapse".
    private var log: [String] = []

    override func setUp() {
        super.setUp()
        time = ManualTime()
        panelOpen = false
        panelChecks = 0
        busy = false
        presses = []
        log = []
    }

    private func makeSession() -> NotificationCenterSession {
        return NotificationCenterSession(
            now: { [unowned self] in time.now },
            after: { [unowned self] in time.after($0, $1) },
            panelIsOpen: { [unowned self] in panelChecks += 1; return panelOpen },
            press: { [unowned self] _, mode, finished in
                guard !busy else { return false }
                log.append("press")
                presses.append((mode, finished))
                return true
            },
            expand: { [unowned self] in log.append("expand") },
            collapse: { [unowned self] in log.append("collapse") })
    }

    private func openPanel(_ session: NotificationCenterSession, collapsed: Bool = true) {
        session.clockClicked(at: CGPoint(x: 1900, y: 12), barCollapsed: collapsed)
        panelOpen = true
        presses.last?.finished(.panelShown)
    }

    func testClickWhileCollapsedExpandsBeforeThePress() {
        let session = makeSession()
        session.clockClicked(at: CGPoint(x: 1900, y: 12), barCollapsed: true)
        XCTAssertEqual(log, ["expand", "press"])
        XCTAssertEqual(presses.first?.mode, .restoreAfterPress)
        XCTAssertTrue(session.isActive)
        XCTAssertTrue(session.expandedBar)
    }

    func testCollapsesWithinOneCheckOfThePanelClosing() {
        let session = makeSession()
        openPanel(session)
        time.advance(to: 7.05)
        XCTAssertEqual(log, ["expand", "press"])
        panelOpen = false
        time.advance(to: 7.2)
        XCTAssertEqual(log, ["expand", "press", "collapse"])
        XCTAssertFalse(session.isActive)
        let checks = panelChecks
        time.advance(to: 60)
        XCTAssertEqual(panelChecks, checks, "checking stops with the collapse")
    }

    func testChecksAtARelaxedRateOnlyWhileWaiting() {
        let session = makeSession()
        session.clockClicked(at: .zero, barCollapsed: true)
        time.advance(to: 1)
        XCTAssertEqual(panelChecks, 0, "nothing is checked before the panel showed")
        panelOpen = true
        presses[0].finished(.panelShown)
        time.advance(to: 11)
        XCTAssertEqual(panelChecks, 101, accuracy: 1, "one check every 0.1 s")
    }

    func testNeverCollapsesABarTheUserHadExpanded() {
        let session = makeSession()
        openPanel(session, collapsed: false)
        XCTAssertEqual(log, ["press"], "already expanded")
        panelOpen = false
        time.advance(to: 1)
        XCTAssertEqual(log, ["press"])
        XCTAssertFalse(session.isActive)
    }

    func testManualToggleWhileOpenClearsTheClaim() {
        let session = makeSession()
        openPanel(session)
        time.advance(to: 3)
        session.userChangedBar()
        XCTAssertFalse(session.expandedBar)
        XCTAssertTrue(session.isActive, "auto-collapse still waits for the panel")
        panelOpen = false
        time.advance(to: 4)
        XCTAssertEqual(log, ["expand", "press"])
        XCTAssertFalse(session.isActive)
    }

    func testCapStopsWaitingAndLeavesTheBarAsItIs() {
        let session = makeSession()
        openPanel(session)
        time.advance(to: 599.9)
        XCTAssertTrue(session.isActive)
        time.advance(to: 600.1)
        XCTAssertFalse(session.isActive)
        XCTAssertEqual(log, ["expand", "press"], "never collapsed unexpectedly")
        let checks = panelChecks
        time.advance(to: 2000)
        XCTAssertEqual(panelChecks, checks)
        panelOpen = false
        time.advance(to: 2001)
        XCTAssertEqual(log, ["expand", "press"])
    }

    func testPressThatOpenedNothingIsRetriedOnceThenTheBarGoesBack() {
        let session = makeSession()
        session.clockClicked(at: .zero, barCollapsed: true)
        presses[0].finished(.noPanel)
        XCTAssertEqual(presses.count, 2)
        XCTAssertEqual(presses[1].mode, .restoreWhenPanelShows)
        presses[1].finished(.noPanel)
        XCTAssertEqual(log, ["expand", "press", "press", "collapse"])
        XCTAssertFalse(session.isActive)
    }

    func testRetryThatOpensThePanelWaitsForItToClose() {
        let session = makeSession()
        session.clockClicked(at: .zero, barCollapsed: true)
        presses[0].finished(.noPanel)
        panelOpen = true
        presses[1].finished(.panelShown)
        time.advance(to: 2)
        XCTAssertEqual(log, ["expand", "press", "press"])
        panelOpen = false
        time.advance(to: 3)
        XCTAssertEqual(log.last, "collapse")
    }

    func testBusyPressIsTriedAgainThenGivenUp() {
        let session = makeSession()
        busy = true
        session.clockClicked(at: .zero, barCollapsed: true)
        XCTAssertTrue(presses.isEmpty)
        time.advance(to: 0.25)
        busy = false
        time.advance(to: 0.35)
        XCTAssertEqual(presses.count, 1, "pressed once the activation landed")

        let stuck = makeSession()
        log = []
        busy = true
        stuck.clockClicked(at: .zero, barCollapsed: true)
        time.advance(to: 5)
        XCTAssertEqual(log, ["expand", "collapse"], "gave up after the busy timeout")
        XCTAssertFalse(stuck.isActive)
    }

    // A click on the clock closes an open panel by itself; the check sees it go.
    func testClickThatClosesThePanelCountsAsTheClose() {
        let session = makeSession()
        openPanel(session)
        time.advance(to: 1)
        panelOpen = false // the user's click on the clock closed it
        time.advance(to: 1.1)
        XCTAssertEqual(log.last, "collapse")
    }

    func testClickBeforeTheCloseWasNoticedKeepsTheClaim() {
        let session = makeSession()
        openPanel(session)
        // Closed and clicked again within one check: the bar is expanded now,
        // but it was Hidden Bar that expanded it.
        session.clockClicked(at: .zero, barCollapsed: false)
        XCTAssertTrue(session.expandedBar)
        panelOpen = true
        presses.last?.finished(.panelShown)
        panelOpen = false
        time.advance(to: 1)
        XCTAssertEqual(log.last, "collapse")
        XCTAssertEqual(log.filter { $0 == "collapse" }.count, 1)
    }
}
