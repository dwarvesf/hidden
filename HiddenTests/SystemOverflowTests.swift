import XCTest
@testable import Hidden_Bar

#if HIDDENBAR_NATIVE_VISIBILITY

/// Contract: on macOS 27 the system « button (MenuBarAgent) swallows status items
/// that do not fit, and there is one « per display. These tests pin how the
/// buttons are found, converted to Cocoa coordinates, and when an item counts as
/// swallowed, using the signals and the two-display layout measured on 27.2.
/// Mock boundary: fake tree nodes stand in for live Accessibility; the check is
/// a pure function over caller-supplied frames and flags.
final class SystemOverflowTests: XCTestCase {

    private final class FakeNode: SystemOverflowNode {
        let identifier: String?
        let frame: CGRect?
        let children: [SystemOverflowNode]

        init(identifier: String? = nil, frame: CGRect? = nil, children: [SystemOverflowNode] = []) {
            self.identifier = identifier
            self.frame = frame
            self.children = children
        }
    }

    private static let closed = "menu-bar-overflow-indicator"

    // Main display, plus a portrait display to its right whose top sits above the main one.
    private let main = CGRect(x: 0, y: 0, width: 1600, height: 900)
    private let portrait = CGRect(x: 1600, y: -342, width: 900, height: 1600)
    private let primaryMaxY: CGFloat = 900

    // Accessibility frames (top-left origin, global).
    private let portraitAXFrame = CGRect(x: 2207.5, y: -357, width: 18, height: 27)
    private let mainAXFrame = CGRect(x: 640, y: 0, width: 18, height: 24)

    private var portraitButton: SystemOverflowButton {
        SystemOverflowButton(state: .closed, frame: CGRect(x: 2207.5, y: 1230, width: 18, height: 27))
    }
    private var mainButton: SystemOverflowButton {
        SystemOverflowButton(state: .closed, frame: CGRect(x: 640, y: 876, width: 18, height: 24))
    }

    // MARK: identifier to state

    func test_identifierMapsToState() {
        XCTAssertEqual(SystemOverflowMatcher.state(forIdentifier: "menu-bar-overflow-indicator"), .closed)
        XCTAssertEqual(SystemOverflowMatcher.state(forIdentifier: "menu-bar-overflow-indicator-expanded"), .open)
        XCTAssertEqual(SystemOverflowMatcher.state(forIdentifier: "menu-bar-overflow-indicator-other"), .absent)
        XCTAssertEqual(SystemOverflowMatcher.state(forIdentifier: nil), .absent)
    }

    // MARK: tree search

    func test_findAllReturnsOneButtonPerDisplay() {
        let tree = FakeNode(children: [
            FakeNode(identifier: "unrelated"),
            FakeNode(children: [FakeNode(children: [FakeNode(identifier: Self.closed, frame: portraitAXFrame)])]),
            FakeNode(children: [FakeNode(identifier: "menu-bar-overflow-indicator-expanded", frame: mainAXFrame)])
        ])
        let found = SystemOverflowMatcher.findAll(in: tree)
        XCTAssertEqual(found.map { $0.state }, [.closed, .open])
        XCTAssertEqual(found.map { $0.node.frame }, [portraitAXFrame, mainAXFrame])
    }

    func test_buttonReachableThroughTwoParentsIsReturnedOnce() {
        let button = FakeNode(identifier: Self.closed, frame: portraitAXFrame)
        let tree = FakeNode(children: [FakeNode(children: [button]), FakeNode(children: [FakeNode(children: [button])])])
        XCTAssertEqual(SystemOverflowMatcher.findAll(in: tree).count, 2)
        XCTAssertEqual(SystemOverflowMatcher.findUnique(in: tree).count, 1)
        XCTAssertEqual(SystemOverflowIndicator(root: { tree }, primaryScreenMaxY: { 900 }).buttons, [portraitButton])
    }

    func test_buttonsOnDifferentDisplaysAreKept() {
        let tree = FakeNode(children: [FakeNode(identifier: Self.closed, frame: portraitAXFrame),
                                       FakeNode(identifier: Self.closed, frame: mainAXFrame)])
        XCTAssertEqual(SystemOverflowMatcher.findUnique(in: tree).count, 2)
    }

    func test_noButtonMeansAbsent() {
        let tree = FakeNode(children: [FakeNode(identifier: "AXMenuBarItem"), FakeNode()])
        XCTAssertTrue(SystemOverflowMatcher.findAll(in: tree).isEmpty)
        XCTAssertEqual(SystemOverflowIndicator(root: { tree }).state, .absent)
        XCTAssertTrue(SystemOverflowIndicator(root: { nil }).buttons.isEmpty)
    }

    func test_searchStopsAtMaxDepth() {
        var node: SystemOverflowNode = FakeNode(identifier: Self.closed)
        for _ in 0...SystemOverflowMatcher.maxDepth { node = FakeNode(children: [node]) }
        XCTAssertTrue(SystemOverflowMatcher.findAll(in: node).isEmpty)
    }

    // MARK: Accessibility to Cocoa frames

    func test_portraitButtonFrameConvertsToCocoa() {
        let cocoa = SystemOverflowMatcher.cocoaFrame(fromAccessibilityFrame: portraitAXFrame, primaryScreenMaxY: primaryMaxY)
        XCTAssertEqual(cocoa, CGRect(x: 2207.5, y: 1230, width: 18, height: 27))
        XCTAssertTrue(portrait.contains(CGPoint(x: cocoa.midX, y: cocoa.midY)))
    }

    func test_indicatorReportsButtonsInCocoaFramesAndAggregateState() {
        let tree = FakeNode(children: [
            FakeNode(identifier: Self.closed, frame: portraitAXFrame),
            FakeNode(identifier: "menu-bar-overflow-indicator-expanded", frame: mainAXFrame)
        ])
        let indicator = SystemOverflowIndicator(root: { tree }, primaryScreenMaxY: { 900 })
        XCTAssertEqual(indicator.buttons, [portraitButton,
                                           SystemOverflowButton(state: .open, frame: mainButton.frame)])
        XCTAssertEqual(indicator.state, .open)
    }

    func test_readButtonsDeliversOnTheMainQueueFromABackgroundRead() {
        let tree = FakeNode(children: [FakeNode(identifier: Self.closed, frame: portraitAXFrame)])
        var readOnMain: Bool?
        let indicator = SystemOverflowIndicator(root: { readOnMain = Thread.isMainThread; return tree },
                                                primaryScreenMaxY: { 900 })
        let done = expectation(description: "read")
        indicator.readButtons { buttons in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(buttons, [self.portraitButton])
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
        XCTAssertEqual(readOnMain, false)
    }

    // MARK: is the item swallowed

    private func swallowed(_ frame: CGRect, hasScreen: Bool = true, visible: Bool,
                           indicators: [SystemOverflowButton]) -> Bool {
        SystemOverflowMatcher.isItemInSystemOverflow(windowFrame: frame, hasScreen: hasScreen,
                                                     occlusionVisible: visible, indicators: indicators)
    }

    func test_noIndicatorIsNeverOverflow() {
        let parked = CGRect(x: 0, y: -30, width: 24, height: 24)
        XCTAssertFalse(swallowed(parked, hasScreen: false, visible: false, indicators: []))
        XCTAssertFalse(swallowed(CGRect(x: 640, y: 876, width: 24, height: 24), visible: false, indicators: []))
    }

    func test_itemParkedOffScreenIsOverflowWhenAnyIndicatorExists() {
        let parked = CGRect(x: 0, y: -30, width: 24, height: 24)
        XCTAssertTrue(swallowed(parked, hasScreen: false, visible: false, indicators: [portraitButton]))
        XCTAssertTrue(swallowed(parked, hasScreen: false, visible: false, indicators: [mainButton, portraitButton]))
    }

    func test_itemStackedUnderMainButtonIsOverflowWhileSecondButtonExists() {
        // Measured: window x around 625-668, occlusion not visible, the portrait « exists too.
        let stacked = CGRect(x: 625, y: 876, width: 43, height: 24)
        XCTAssertTrue(swallowed(stacked, visible: false, indicators: [portraitButton, mainButton]))
        XCTAssertTrue(swallowed(stacked, visible: false, indicators: [mainButton, portraitButton]))
    }

    func test_visibleItemOnMainBarIsNotOverflowWhenOnlyPortraitButtonExists() {
        let onBar = CGRect(x: 800, y: 876, width: 24, height: 24)
        XCTAssertFalse(swallowed(onBar, visible: true, indicators: [portraitButton]))
    }

    func test_hiddenItemAwayFromEveryButtonIsNotOverflow() {
        // An auto-hidden menu bar also clears occlusion; the item is not on a «.
        let away = CGRect(x: 800, y: 876, width: 24, height: 24)
        XCTAssertFalse(swallowed(away, visible: false, indicators: [portraitButton, mainButton]))
    }

    func test_visibleItemOnAButtonIsNotOverflow() {
        let onButton = CGRect(x: 625, y: 876, width: 43, height: 24)
        XCTAssertFalse(swallowed(onButton, visible: true, indicators: [mainButton]))
    }

    func test_itemNextToButtonButNotUnderItIsNotOverflow() {
        // A fullscreen Space with an auto-hidden bar clears occlusion; an arrow beside « is not under it.
        let beside = CGRect(x: 660, y: 876, width: 24, height: 24)
        XCTAssertTrue(beside.intersects(mainButton.frame!.insetBy(dx: -4, dy: -4)))
        XCTAssertFalse(swallowed(beside, visible: false, indicators: [mainButton, portraitButton]))
    }

    func test_buttonWithoutFrameNeverMatchesByPosition() {
        let unreadable = SystemOverflowButton(state: .closed, frame: nil)
        XCTAssertFalse(swallowed(CGRect(x: 625, y: 876, width: 43, height: 24), visible: false, indicators: [unreadable]))
    }

    // MARK: one-time notice

    func test_noticeShowsOnceThenRemembers() {
        let suite = "SystemOverflowTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let policy = SystemOverflowNoticePolicy(defaults: defaults)
        XCTAssertTrue(policy.shouldShow())
        policy.recordShown()
        XCTAssertFalse(policy.shouldShow())
        XCTAssertFalse(SystemOverflowNoticePolicy(defaults: defaults).shouldShow())
    }

    // MARK: expand notice: the decision

    func test_expandNoticeShowsOnlyWhenExpandedAndItemInOverflowAndNotShown() {
        for isExpanded in [true, false] {
            for inOverflow in [true, false] {
                for alreadyShown in [true, false] {
                    let show = SystemOverflowNoticePolicy.shouldShowAfterExpand(
                        isExpanded: isExpanded, hiddenItemInOverflow: inOverflow, alreadyShown: alreadyShown)
                    XCTAssertEqual(show, isExpanded && inOverflow && !alreadyShown,
                                   "expanded \(isExpanded), in overflow \(inOverflow), shown \(alreadyShown)")
                }
            }
        }
    }

    func test_expandNoticeFlagIsSeparateFromTheCollapseNotice() {
        let suite = "SystemOverflowTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let policy = SystemOverflowNoticePolicy(defaults: defaults)
        policy.recordShown()
        XCTAssertTrue(policy.shouldShowAfterExpand())
        policy.recordExpandShown()
        XCTAssertFalse(policy.shouldShowAfterExpand())
        XCTAssertFalse(SystemOverflowNoticePolicy(defaults: defaults).shouldShowAfterExpand())

        let other = UserDefaults(suiteName: suite + ".other")!
        defer { other.removePersistentDomain(forName: suite + ".other") }
        let fresh = SystemOverflowNoticePolicy(defaults: other)
        fresh.recordExpandShown()
        XCTAssertTrue(fresh.shouldShow(), "the expand notice does not silence the collapse notice")
    }

    // MARK: expand notice: which hidden apps are in «

    private func item(_ bundle: String, _ axFrame: CGRect, unreadable: Bool = false) -> MenuBarInventoryItem {
        MenuBarInventoryItem(bundleIdentifier: bundle, frame: axFrame, isUnreadable: unreadable)
    }

    private func overflowed(hidden: Set<String>, running: Set<String>? = nil,
                            inventory: [MenuBarInventoryItem], indicators: [SystemOverflowButton]) -> Set<String> {
        SystemOverflowExpandMatcher.bundlesInOverflow(
            hidden: hidden, running: running ?? hidden, inventory: inventory, indicators: indicators,
            displays: MenuBarDisplay.displays(screenFrames: [main, portrait]), primaryScreenMaxY: primaryMaxY)
    }

    private let onBar = CGRect(x: 900, y: 0, width: 24, height: 24)

    func test_hiddenAppMissingFromAccessibilityWhileButtonExistsIsInOverflow() {
        let result = overflowed(hidden: ["a.app", "b.app"], inventory: [item("a.app", onBar)], indicators: [mainButton])
        XCTAssertEqual(result, ["b.app"])
    }

    func test_nothingIsInOverflowWithoutAButton() {
        XCTAssertEqual(overflowed(hidden: ["a.app"], inventory: [], indicators: []), [])
    }

    func test_everyHiddenAppOnTheBarMeansNoOverflow() {
        let result = overflowed(hidden: ["a.app", "b.app"],
                                inventory: [item("a.app", onBar), item("b.app", onBar.offsetBy(dx: 30, dy: 0))],
                                indicators: [mainButton])
        XCTAssertEqual(result, [])
    }

    func test_hiddenAppListedUnderTheButtonIsInOverflow() {
        let result = overflowed(hidden: ["a.app"], inventory: [item("a.app", mainAXFrame)], indicators: [mainButton])
        XCTAssertEqual(result, ["a.app"])
    }

    func test_hiddenAppListedOnNoDisplayIsInOverflow() {
        let off = CGRect(x: 0, y: 5000, width: 24, height: 24)
        let result = overflowed(hidden: ["a.app"], inventory: [item("a.app", off)], indicators: [mainButton])
        XCTAssertEqual(result, ["a.app"])
    }

    func test_oneOverflowedItemOfSeveralCounts() {
        let result = overflowed(hidden: ["a.app"],
                                inventory: [item("a.app", onBar), item("a.app", mainAXFrame)],
                                indicators: [mainButton])
        XCTAssertEqual(result, ["a.app"])
    }

    func test_appThatDidNotAnswerAccessibilityIsNotJudged() {
        let result = overflowed(hidden: ["a.app"], inventory: [item("a.app", .zero, unreadable: true)], indicators: [mainButton])
        XCTAssertEqual(result, [])
    }

    func test_appThatIsNotRunningIsNotCounted() {
        let result = overflowed(hidden: ["a.app", "b.app"], running: ["a.app"],
                                inventory: [item("a.app", onBar)], indicators: [mainButton])
        XCTAssertEqual(result, [])
    }

    func test_systemExtrasAreNotCounted() {
        let result = overflowed(hidden: ["com.apple.controlcenter", "com.apple.MenuBarAgent"],
                                inventory: [], indicators: [mainButton])
        XCTAssertEqual(result, [])
    }

    func test_buttonWithoutFrameStillCountsAnAppMissingFromTheList() {
        let unreadable = SystemOverflowButton(state: .closed, frame: nil)
        XCTAssertEqual(overflowed(hidden: ["a.app"], inventory: [], indicators: [unreadable]), ["a.app"])
        XCTAssertEqual(overflowed(hidden: ["a.app"], inventory: [item("a.app", mainAXFrame)], indicators: [unreadable]), [])
    }
}

#endif
