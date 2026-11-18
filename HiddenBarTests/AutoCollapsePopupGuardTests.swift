//
//  AutoCollapsePopupGuardTests.swift
//  HiddenBarTests
//
//  Copyright © 2026 Console Labs. All rights reserved.
//

import AppKit
import XCTest

private final class FakeWindowList: OnScreenWindowListing {
    var windows: [OnScreenWindow] = []
    var reads = 0

    func onScreenWindows() -> [OnScreenWindow] {
        reads += 1
        return windows
    }
}

final class AutoCollapsePopupGuardTests: XCTestCase {
    private let ownPID: pid_t = 1
    private let netMonitor: pid_t = 42
    private let notificationCenter: pid_t = 50
    private let documentApp: pid_t = 60

    private var list: FakeWindowList!
    private var time: TimeInterval = 0
    private var owners: Set<String> = []
    private var ownerReads = 0
    private var logged: [String] = []

    // A 1600 x 900 display with a 24 pt menu bar, and a 900 x 1600 one to its
    // right, raised so its menu bar sits higher.
    private let displays = [
        PopupGuardDisplay(menuBarBand: CGRect(x: 0, y: 0, width: 1600, height: 24), height: 900),
        PopupGuardDisplay(menuBarBand: CGRect(x: 1600, y: -358, width: 900, height: 24), height: 1600),
    ]

    override func setUp() {
        super.setUp()
        list = FakeWindowList()
        time = 0
        owners = ["com.example.netmon"]
        ownerReads = 0
        logged = []
    }

    private func makeGuard() -> AutoCollapsePopupGuard {
        let bundles: [pid_t: String] = [
            ownPID: "com.dwarvesv.minimalbar",
            netMonitor: "com.example.netmon",
            notificationCenter: AutoCollapsePopupGuard.notificationCenterBundleIdentifier,
            documentApp: "com.example.editor",
        ]
        return AutoCollapsePopupGuard(windows: list,
                                      displays: { [unowned self] in displays },
                                      bundleIdentifier: { bundles[$0] },
                                      menuBarItemOwners: { [unowned self] in ownerReads += 1; return owners },
                                      now: { [unowned self] in time },
                                      ownPID: ownPID,
                                      log: { [unowned self] in logged.append($0) })
    }

    private func window(_ pid: pid_t, layer: Int, _ frame: CGRect) -> OnScreenWindow {
        return OnScreenWindow(ownerPID: pid, layer: layer, frame: frame)
    }

    private var popUpMenu: Int { AutoCollapsePopupGuard.popUpMenuLayer }
    private var status: Int { AutoCollapsePopupGuard.statusLayer }

    // MARK: - Defer and collapse

    func testNothingIsReadUntilTheTimerFires() {
        let popupGuard = makeGuard()
        XCTAssertEqual(list.reads, 0)
        _ = popupGuard.defersCollapse()
        XCTAssertEqual(list.reads, 1, "one window-list read per timer fire")
    }

    func testOpenPopupMenuDefersEveryFire() {
        let popupGuard = makeGuard()
        list.windows = [window(netMonitor, layer: popUpMenu, CGRect(x: 1200, y: 24, width: 300, height: 400))]
        XCTAssertTrue(popupGuard.defersCollapse())
        time = 10
        XCTAssertTrue(popupGuard.defersCollapse(), "re-armed, still open")
    }

    // A field report can then name what held auto-collapse (#524): the owner and
    // layer, once per hold, and nothing the window shows.
    func testLogsTheHoldingWindowOncePerHold() {
        let popupGuard = makeGuard()
        list.windows = [window(netMonitor, layer: popUpMenu, CGRect(x: 1200, y: 24, width: 300, height: 400))]
        XCTAssertTrue(popupGuard.defersCollapse())
        time = 10
        XCTAssertTrue(popupGuard.defersCollapse())
        XCTAssertEqual(logged, ["AutoCollapse: holding for a popup from com.example.netmon at layer \(popUpMenu)"])

        list.windows = []
        XCTAssertFalse(popupGuard.defersCollapse())
        list.windows = [window(99, layer: status, CGRect(x: 823, y: 26, width: 315, height: 93))]
        XCTAssertTrue(popupGuard.defersCollapse())
        XCTAssertEqual(logged.last, "AutoCollapse: holding for a popup from pid 99 at layer \(status)", "a new hold logs again")
        XCTAssertEqual(logged.count, 2)
    }

    // #319: a network monitor's graph is a status-level panel under its item.
    func testStatusLevelPopoverDefers() {
        let popupGuard = makeGuard()
        list.windows = [window(netMonitor, layer: status, CGRect(x: 823, y: 26, width: 315, height: 93))]
        XCTAssertTrue(popupGuard.defersCollapse())
    }

    func testBarCollapsesOnceThePopupCloses() {
        let popupGuard = makeGuard()
        list.windows = [window(netMonitor, layer: popUpMenu, CGRect(x: 1200, y: 24, width: 300, height: 400))]
        XCTAssertTrue(popupGuard.defersCollapse())
        list.windows = []
        time = 10
        XCTAssertFalse(popupGuard.defersCollapse())
    }

    func testNoPopupCollapses() {
        XCTAssertFalse(makeGuard().defersCollapse())
    }

    // MARK: - Cap

    func testCapCollapsesAfterTenMinutesEvenWithThePopupOpen() {
        let popupGuard = makeGuard()
        list.windows = [window(netMonitor, layer: popUpMenu, CGRect(x: 1200, y: 24, width: 300, height: 400))]
        time = 5
        XCTAssertTrue(popupGuard.defersCollapse())
        time = 5 + 599
        XCTAssertTrue(popupGuard.defersCollapse())
        time = 5 + 600
        XCTAssertFalse(popupGuard.defersCollapse(), "the cap wins")
        time = 5 + 610
        XCTAssertFalse(popupGuard.defersCollapse(), "until the bar is expanded again")

        popupGuard.reset()
        time = 700
        XCTAssertTrue(popupGuard.defersCollapse(), "a new expansion starts the cap over")
    }

    func testCapStartsOverAfterThePopupCloses() {
        let popupGuard = makeGuard()
        let popup = window(netMonitor, layer: popUpMenu, CGRect(x: 1200, y: 24, width: 300, height: 400))
        list.windows = [popup]
        XCTAssertTrue(popupGuard.defersCollapse())
        time = 300
        XCTAssertTrue(popupGuard.defersCollapse())
        list.windows = []
        time = 310
        XCTAssertFalse(popupGuard.defersCollapse())
        list.windows = [popup]
        time = 320
        XCTAssertTrue(popupGuard.defersCollapse())
        time = 900
        XCTAssertTrue(popupGuard.defersCollapse(), "counted from 320, not 0")
        time = 920
        XCTAssertFalse(popupGuard.defersCollapse())
    }

    // MARK: - What counts

    func testHiddenBarsOwnWindowsAreIgnored() {
        let popupGuard = makeGuard()
        list.windows = [
            window(ownPID, layer: popUpMenu, CGRect(x: 1300, y: 24, width: 200, height: 120)),
            window(ownPID, layer: status, CGRect(x: 1300, y: 24, width: 300, height: 300)),
            window(ownPID, layer: 0, CGRect(x: 600, y: 24, width: 500, height: 400)),
        ]
        XCTAssertFalse(popupGuard.defersCollapse(), "the context menu and the notch overflow are ours; Preferences defers on its own")
    }

    // Notification Center opened from the clock on a bar the user expanded:
    // the engine's own clock session does not track it.
    func testNotificationCenterOnAUserExpandedBarDefers() {
        let popupGuard = makeGuard()
        list.windows = [window(notificationCenter, layer: 23, CGRect(x: 0, y: 0, width: 1600, height: 900))]
        XCTAssertTrue(popupGuard.defersCollapse())
        list.windows = []
        XCTAssertFalse(popupGuard.defersCollapse(), "closed")
    }

    func testNotificationBannersAndWidgetsDoNotDefer() {
        let popupGuard = makeGuard()
        list.windows = [
            window(notificationCenter, layer: 23, CGRect(x: 1240, y: 30, width: 350, height: 90)),
            window(notificationCenter, layer: -2147483601, CGRect(x: 8, y: 40, width: 360, height: 700)),
        ]
        XCTAssertFalse(popupGuard.defersCollapse())
    }

    func testMenuBarAppWindowUnderTheBarDefers() {
        let popupGuard = makeGuard()
        list.windows = [window(netMonitor, layer: 0, CGRect(x: 1250, y: 28, width: 320, height: 480))]
        XCTAssertTrue(popupGuard.defersCollapse(), "the engine read this app's item in the menu bar")

        owners = []
        XCTAssertFalse(popupGuard.defersCollapse(), "an app with no menu-bar item")
    }

    // Before macOS 27 every item is a status window in the band.
    func testStatusItemWindowNamesItsOwner() {
        let popupGuard = makeGuard()
        owners = []
        let item = window(documentApp, layer: status, CGRect(x: 1300, y: 0, width: 22, height: 24))
        list.windows = [item]
        XCTAssertFalse(popupGuard.defersCollapse(), "an item alone is no popup")
        list.windows = [item, window(documentApp, layer: 3, CGRect(x: 1180, y: 24, width: 260, height: 300))]
        XCTAssertTrue(popupGuard.defersCollapse())
    }

    func testOrdinaryWindowsDoNotDefer() {
        let popupGuard = makeGuard()
        list.windows = [
            // The menu bar itself.
            window(99, layer: 24, CGRect(x: 0, y: 0, width: 1600, height: 24)),
            // A menu-bar app's zoomed document window.
            window(netMonitor, layer: 0, CGRect(x: 0, y: 24, width: 1600, height: 876)),
            // A context menu in the middle of the screen.
            window(documentApp, layer: popUpMenu, CGRect(x: 600, y: 400, width: 200, height: 160)),
            // An app's window at the top, with no menu-bar item.
            window(documentApp, layer: 0, CGRect(x: 100, y: 24, width: 400, height: 300)),
        ]
        XCTAssertFalse(popupGuard.defersCollapse())
        XCTAssertEqual(ownerReads, 1, "item owners are asked for only when a candidate window needs them")
    }

    func testPopupUnderASecondDisplaysMenuBarDefers() {
        let popupGuard = makeGuard()
        list.windows = [window(netMonitor, layer: popUpMenu, CGRect(x: 2100, y: -334, width: 280, height: 300))]
        XCTAssertTrue(popupGuard.defersCollapse())
    }

    func testPopoverArrowGapUnderTheBarStillCounts() {
        let popupGuard = makeGuard()
        list.windows = [window(netMonitor, layer: popUpMenu, CGRect(x: 1200, y: 30, width: 300, height: 400))]
        XCTAssertTrue(popupGuard.defersCollapse())
        list.windows = [window(netMonitor, layer: popUpMenu, CGRect(x: 1200, y: 60, width: 300, height: 400))]
        XCTAssertFalse(popupGuard.defersCollapse(), "too far below the bar")
    }
}
