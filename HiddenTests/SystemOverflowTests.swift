import XCTest
@testable import Hidden_Bar

/// Contract: on macOS 27 the system « button (MenuBarAgent) swallows status items
/// that do not fit. These tests pin how the button is found in the Accessibility
/// tree and when an item counts as swallowed, using the signals measured on 27.2.
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

    private let indicatorFrame = CGRect(x: 1000, y: 0, width: 24, height: 24)

    // MARK: identifier to state

    func test_identifierMapsToState() {
        XCTAssertEqual(SystemOverflowMatcher.state(forIdentifier: "menu-bar-overflow-indicator"), .closed)
        XCTAssertEqual(SystemOverflowMatcher.state(forIdentifier: "menu-bar-overflow-indicator-expanded"), .open)
        XCTAssertEqual(SystemOverflowMatcher.state(forIdentifier: "menu-bar-overflow-indicator-other"), .absent)
        XCTAssertEqual(SystemOverflowMatcher.state(forIdentifier: nil), .absent)
    }

    // MARK: tree search

    func test_findsButtonNestedUnderMenuBar() {
        let button = FakeNode(identifier: "menu-bar-overflow-indicator", frame: indicatorFrame)
        let tree = FakeNode(children: [
            FakeNode(identifier: "unrelated"),
            FakeNode(children: [FakeNode(children: [button])])
        ])
        let found = SystemOverflowMatcher.find(in: tree)
        XCTAssertEqual(found?.state, .closed)
        XCTAssertTrue(found?.node.frame == indicatorFrame)
    }

    func test_findsOpenButton() {
        let tree = FakeNode(children: [FakeNode(identifier: "menu-bar-overflow-indicator-expanded")])
        XCTAssertEqual(SystemOverflowMatcher.find(in: tree)?.state, .open)
    }

    func test_noButtonMeansAbsent() {
        let tree = FakeNode(children: [FakeNode(identifier: "AXMenuBarItem"), FakeNode()])
        XCTAssertNil(SystemOverflowMatcher.find(in: tree))
        XCTAssertEqual(SystemOverflowIndicator(root: { tree }).reading, SystemOverflowReading(state: .absent, frame: nil))
        XCTAssertEqual(SystemOverflowIndicator(root: { nil }).state, .absent)
    }

    func test_searchStopsAtMaxDepth() {
        var node: SystemOverflowNode = FakeNode(identifier: "menu-bar-overflow-indicator")
        for _ in 0...SystemOverflowMatcher.maxDepth { node = FakeNode(children: [node]) }
        XCTAssertNil(SystemOverflowMatcher.find(in: node))
    }

    func test_indicatorReportsStateFrameAndPresses() {
        let button = FakeNode(identifier: "menu-bar-overflow-indicator", frame: indicatorFrame)
        let indicator = SystemOverflowIndicator(root: { FakeNode(children: [button]) })
        XCTAssertEqual(indicator.state, .closed)
        XCTAssertEqual(indicator.frame, indicatorFrame)
        XCTAssertTrue(indicator.press())
        XCTAssertEqual(button.pressCount, 1)
        XCTAssertFalse(SystemOverflowIndicator(root: { nil }).press())
    }

    // MARK: is the item swallowed

    private func swallowed(frame: CGRect, hasScreen: Bool, visible: Bool,
                           state: SystemOverflowState, indicator: CGRect?) -> Bool {
        SystemOverflowMatcher.isItemInSystemOverflow(windowFrame: frame,
                                                     hasScreen: hasScreen,
                                                     occlusionVisible: visible,
                                                     indicatorState: state,
                                                     indicatorFrame: indicator)
    }

    func test_indicatorAbsentIsNeverOverflow() {
        let parked = CGRect(x: 0, y: -30, width: 24, height: 24)
        XCTAssertFalse(swallowed(frame: parked, hasScreen: false, visible: false, state: .absent, indicator: nil))
        XCTAssertFalse(swallowed(frame: CGRect(x: 1000, y: 1400, width: 24, height: 24),
                                 hasScreen: true, visible: false, state: .absent, indicator: indicatorFrame))
    }

    func test_itemParkedOffScreenIsOverflow() {
        let parked = CGRect(x: 0, y: -30, width: 24, height: 24)
        XCTAssertTrue(swallowed(frame: parked, hasScreen: false, visible: false, state: .closed, indicator: indicatorFrame))
        XCTAssertTrue(swallowed(frame: parked, hasScreen: false, visible: false, state: .open, indicator: nil))
    }

    func test_itemStackedAtIndicatorWithoutOcclusionIsOverflow() {
        let stacked = CGRect(x: 1002, y: 1400, width: 24, height: 24)
        XCTAssertTrue(swallowed(frame: stacked, hasScreen: true, visible: false, state: .closed, indicator: indicatorFrame))
    }

    func test_visibleItemIsNotOverflow() {
        let normal = CGRect(x: 800, y: 1400, width: 24, height: 24)
        XCTAssertFalse(swallowed(frame: normal, hasScreen: true, visible: true, state: .closed, indicator: indicatorFrame))
        let overIndicator = CGRect(x: 1002, y: 1400, width: 24, height: 24)
        XCTAssertFalse(swallowed(frame: overIndicator, hasScreen: true, visible: true, state: .closed, indicator: indicatorFrame))
    }

    func test_occlusionAloneIsNotOverflow() {
        // An auto-hidden menu bar clears occlusion too; the item is not at the « button.
        let away = CGRect(x: 800, y: 1400, width: 24, height: 24)
        XCTAssertFalse(swallowed(frame: away, hasScreen: true, visible: false, state: .closed, indicator: indicatorFrame))
        XCTAssertFalse(swallowed(frame: away, hasScreen: true, visible: false, state: .closed, indicator: nil))
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
