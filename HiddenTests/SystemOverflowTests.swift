import XCTest
@testable import Hidden_Bar

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
        private(set) var pressCount = 0

        init(identifier: String? = nil, frame: CGRect? = nil, children: [SystemOverflowNode] = []) {
            self.identifier = identifier
            self.frame = frame
            self.children = children
        }

        func press() -> Bool {
            pressCount += 1
            return true
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

    func test_buttonWithoutFrameNeverMatchesByPosition() {
        let unreadable = SystemOverflowButton(state: .closed, frame: nil)
        XCTAssertFalse(swallowed(CGRect(x: 625, y: 876, width: 43, height: 24), visible: false, indicators: [unreadable]))
    }

    // MARK: pressing the right display's «

    private func pressed(window: CGRect?) -> (result: Bool, main: Int, portrait: Int) {
        let mainNode = FakeNode(identifier: Self.closed, frame: mainAXFrame)
        let portraitNode = FakeNode(identifier: Self.closed, frame: portraitAXFrame)
        let indicator = SystemOverflowIndicator(root: { FakeNode(children: [portraitNode, mainNode]) },
                                                primaryScreenMaxY: { 900 },
                                                displays: { [self.main, self.portrait] },
                                                mainDisplay: { self.main })
        let result = indicator.press(onDisplayOf: window)
        return (result, mainNode.pressCount, portraitNode.pressCount)
    }

    func test_pressOpensTheButtonOnTheArrowsOwnDisplay() {
        let onMain = pressed(window: CGRect(x: 700, y: 876, width: 24, height: 24))
        XCTAssertEqual([onMain.main, onMain.portrait], [1, 0])
        XCTAssertTrue(onMain.result)
        let onPortrait = pressed(window: CGRect(x: 2100, y: 1233, width: 24, height: 24))
        XCTAssertEqual([onPortrait.main, onPortrait.portrait], [0, 1])
    }

    func test_pressFallsBackToMainDisplayWhenParked() {
        let parked = pressed(window: CGRect(x: 0, y: -30, width: 24, height: 24))
        XCTAssertEqual([parked.main, parked.portrait], [1, 0])
        let unknown = pressed(window: nil)
        XCTAssertEqual([unknown.main, unknown.portrait], [1, 0])
    }

    func test_pressIsFalseWhenThatDisplayHasNoButton() {
        let portraitNode = FakeNode(identifier: Self.closed, frame: portraitAXFrame)
        let indicator = SystemOverflowIndicator(root: { FakeNode(children: [portraitNode]) },
                                                primaryScreenMaxY: { 900 },
                                                displays: { [self.main, self.portrait] },
                                                mainDisplay: { self.main })
        XCTAssertFalse(indicator.press(onDisplayOf: CGRect(x: 700, y: 876, width: 24, height: 24)))
        XCTAssertEqual(portraitNode.pressCount, 0)
        XCTAssertFalse(SystemOverflowIndicator(root: { nil }).press(onDisplayOf: nil))
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
}
