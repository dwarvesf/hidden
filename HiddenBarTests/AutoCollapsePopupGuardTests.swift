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
    private let controlCenter: pid_t = 70
    private let documentApp: pid_t = 60

    private var list: FakeWindowList!
    private var time: TimeInterval = 0
    private var owners: Set<String> = []
    private var ownerReads = 0
    private var panelOpen = true
    private var panelReads = 0
    private var nextWindowNumber = 10_000
    private var logged: [String] = []
    private var loggedPublic: [String] = []

    // A 1600 x 900 display with a 24 pt menu bar, and a 900 x 1600 one to its
    // right, raised so its menu bar sits higher.
    private var displays = [
        PopupGuardDisplay(menuBarBand: CGRect(x: 0, y: 0, width: 1600, height: 24), height: 900),
        PopupGuardDisplay(menuBarBand: CGRect(x: 1600, y: -358, width: 900, height: 24), height: 1600),
    ]

    override func setUp() {
        super.setUp()
        list = FakeWindowList()
        time = 0
        owners = ["com.example.netmon"]
        ownerReads = 0
        panelOpen = true
        panelReads = 0
        nextWindowNumber = 10_000
        logged = []
        loggedPublic = []
    }

    private func makeGuard() -> AutoCollapsePopupGuard {
        let bundles: [pid_t: String] = [
            ownPID: "com.dwarvesv.minimalbar",
            netMonitor: "com.example.netmon",
            notificationCenter: AutoCollapsePopupGuard.notificationCenterBundleIdentifier,
            documentApp: "com.example.editor",
            controlCenter: "com.apple.controlcenter",
        ]
        return AutoCollapsePopupGuard(windows: list,
                                      displays: { [unowned self] in displays },
                                      bundleIdentifier: { bundles[$0] },
                                      menuBarItemOwners: { [unowned self] in ownerReads += 1; return owners },
                                      notificationCenterPanelIsOpen: { [unowned self] in panelReads += 1; return panelOpen },
                                      now: { [unowned self] in time },
                                      ownPID: ownPID,
                                      log: { [unowned self] in logged.append($0) },
                                      logPublic: { [unowned self] in loggedPublic.append("\($0)") })
    }

    // Unnumbered windows get unique numbers, so they cannot collide in the baseline.
    private func window(_ pid: pid_t, layer: Int, _ frame: CGRect, number: Int? = nil) -> OnScreenWindow {
        defer { nextWindowNumber += 1 }
        return OnScreenWindow(ownerPID: pid, layer: layer, frame: frame, number: number ?? nextWindowNumber)
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

    // The public log gets a line that names no app, window or layer; the detail
    // stays in the private line above.
    func testPublicLineIsStaticAndLoggedOncePerHold() {
        let popupGuard = makeGuard()
        list.windows = [window(netMonitor, layer: popUpMenu, CGRect(x: 1200, y: 24, width: 300, height: 400))]
        XCTAssertTrue(popupGuard.defersCollapse())
        time = 10
        XCTAssertTrue(popupGuard.defersCollapse())
        XCTAssertEqual(loggedPublic, ["AutoCollapse: holding for a menu bar popup"])
        XCTAssertFalse(loggedPublic.joined().contains("netmon"))
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
        XCTAssertEqual(loggedPublic.last, "AutoCollapse: a menu bar popup held auto-hide for the full limit; collapsing anyway")
        time = 5 + 610
        XCTAssertFalse(popupGuard.defersCollapse(), "until the bar is expanded again")

        list.windows = []
        popupGuard.reset()
        list.windows = [window(netMonitor, layer: popUpMenu, CGRect(x: 1200, y: 24, width: 300, height: 400))]
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

    // macOS 27 keeps a screen-tall Notification Center window up under a plain
    // notification banner; the panel itself is not open, so the bar may collapse.
    func testTallNotificationCenterWindowWithoutThePanelDoesNotDefer() {
        let popupGuard = makeGuard()
        panelOpen = false
        list.windows = [window(notificationCenter, layer: 23, CGRect(x: 0, y: 0, width: 1600, height: 900))]
        XCTAssertFalse(popupGuard.defersCollapse())
        XCTAssertEqual(panelReads, 1)
    }

    func testTallNotificationCenterWindowWithThePanelOpenDefers() {
        let popupGuard = makeGuard()
        panelOpen = true
        list.windows = [window(notificationCenter, layer: 23, CGRect(x: 0, y: 0, width: 1600, height: 900))]
        XCTAssertTrue(popupGuard.defersCollapse())
        XCTAssertEqual(panelReads, 1)
    }

    func testPanelCheckRunsOnlyWhenANotificationCenterWindowIsFound() {
        let popupGuard = makeGuard()
        list.windows = [
            window(notificationCenter, layer: 23, CGRect(x: 1240, y: 30, width: 350, height: 90)),
            window(netMonitor, layer: popUpMenu, CGRect(x: 1200, y: 24, width: 300, height: 400)),
        ]
        XCTAssertTrue(popupGuard.defersCollapse())
        XCTAssertEqual(panelReads, 0, "a banner and a menu need no Accessibility read")
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

    // KVM hot borders and similar tools keep a 1 pt window on the screen edge.
    func testThinEdgeWindowsDoNotDefer() {
        let popupGuard = makeGuard()
        list.windows = [
            window(netMonitor, layer: 0, CGRect(x: 0, y: 0, width: 1, height: 900)),
            window(99, layer: status, CGRect(x: 1599, y: 0, width: 1, height: 900)),
            window(99, layer: status, CGRect(x: 0, y: 24, width: 1600, height: 4)),
        ]
        XCTAssertFalse(popupGuard.defersCollapse())
    }

    // A side-notes app keeps a thin strip flush at the screen edge, top to bottom,
    // and opens a panel of the same height from it.
    func testScreenTallSideStripDoesNotDefer() {
        let popupGuard = makeGuard()
        list.windows = [window(netMonitor, layer: 3, CGRect(x: 1590, y: 0, width: 10, height: 900))]
        XCTAssertFalse(popupGuard.defersCollapse(), "an app with a menu bar icon, but no popup")
    }

    func testScreenTallSidePanelDoesNotDeferAtNormalLayers() {
        let popupGuard = makeGuard()
        for layer in [3, 24] {
            list.windows = [window(netMonitor, layer: layer, CGRect(x: 1200, y: 0, width: 400, height: 900))]
            XCTAssertFalse(popupGuard.defersCollapse(), "layer \(layer)")
        }
    }

    // Measured on macOS 27.2.1, 960 x 600 pt display: the open Control Center
    // panel is a pop-up menu level window from the display top, taller than the display.
    func testScreenTallControlCenterPanelDefers() {
        displays = [PopupGuardDisplay(menuBarBand: CGRect(x: 0, y: 0, width: 960, height: 24), height: 600)]
        let popupGuard = makeGuard()
        list.windows = [window(controlCenter, layer: popUpMenu, CGRect(x: 480, y: 0, width: 656, height: 964))]
        XCTAssertTrue(popupGuard.defersCollapse())
    }

    func testScreenTallStatusLevelWindowDefers() {
        let popupGuard = makeGuard()
        list.windows = [window(netMonitor, layer: status, CGRect(x: 1200, y: 0, width: 400, height: 900))]
        XCTAssertTrue(popupGuard.defersCollapse())
    }

    // A side-notes app on the same 600 pt display: a 10 pt strip and its 400 pt panel.
    func testSideNotesStripAndPanelOnA600PointDisplayDoNotDefer() {
        displays = [PopupGuardDisplay(menuBarBand: CGRect(x: 0, y: 0, width: 960, height: 24), height: 600)]
        let popupGuard = makeGuard()
        list.windows = [window(netMonitor, layer: 3, CGRect(x: 950, y: 0, width: 10, height: 600))]
        XCTAssertFalse(popupGuard.defersCollapse(), "strip")
        for layer in [3, 24] {
            list.windows = [window(netMonitor, layer: layer, CGRect(x: 560, y: 0, width: 400, height: 600))]
            XCTAssertFalse(popupGuard.defersCollapse(), "panel at layer \(layer)")
        }
    }

    func testScreenTallWindowOnASecondDisplayDoesNotDefer() {
        let popupGuard = makeGuard()
        list.windows = [window(netMonitor, layer: 3, CGRect(x: 2490, y: -358, width: 10, height: 1600))]
        XCTAssertFalse(popupGuard.defersCollapse())
    }

    // Starting at the band's bottom edge, it stops a bar short of the display top.
    func testPopupFromTheBarsBottomToTheDisplayBottomStillDefers() {
        let popupGuard = makeGuard()
        for layer in [3, 24, status, popUpMenu] {
            list.windows = [window(netMonitor, layer: layer, CGRect(x: 1200, y: 24, width: 400, height: 876))]
            XCTAssertTrue(popupGuard.defersCollapse(), "layer \(layer)")
        }
    }

    func testWindowAFewPointsShortOfFullHeightStillDefers() {
        let popupGuard = makeGuard()
        list.windows = [window(netMonitor, layer: 3, CGRect(x: 1590, y: 0, width: 10, height: 897))]
        XCTAssertTrue(popupGuard.defersCollapse())
    }

    func testPopupStartingAboveTheBarDefers() {
        let popupGuard = makeGuard()
        list.windows = [window(netMonitor, layer: popUpMenu, CGRect(x: 1200, y: -6, width: 300, height: 400))]
        XCTAssertTrue(popupGuard.defersCollapse())
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

    // MARK: - Baseline: a window already on screen when the bar expands is furniture

    // A notch app keeps one status-level window at the top: same number at rest,
    // on hover and for the whole run.
    private let notchWindow = CGRect(x: 0, y: -1, width: 960, height: 400)
    private let notchDisplay = PopupGuardDisplay(menuBarBand: CGRect(x: 0, y: 0, width: 960, height: 24), height: 600)

    func testWindowPresentAtResetIsFurnitureNotAPopup() {
        displays = [notchDisplay]
        let popupGuard = makeGuard()
        list.windows = [window(netMonitor, layer: status, notchWindow, number: 500)]
        popupGuard.reset()
        XCTAssertFalse(popupGuard.defersCollapse())
        time = 10
        XCTAssertFalse(popupGuard.defersCollapse(), "still the same window on the next fire")
        XCTAssertTrue(logged.isEmpty)
        XCTAssertTrue(loggedPublic.isEmpty)
    }

    func testSameWindowAbsentFromTheBaselineDefersAsBefore() {
        displays = [notchDisplay]
        let popupGuard = makeGuard()
        list.windows = []
        popupGuard.reset()
        list.windows = [window(netMonitor, layer: status, notchWindow, number: 500)]
        XCTAssertTrue(popupGuard.defersCollapse(), "it appeared after the bar expanded")
    }

    func testPopupMenuAppearingAfterResetDefers() {
        let popupGuard = makeGuard()
        list.windows = []
        popupGuard.reset()
        list.windows = [window(netMonitor, layer: popUpMenu, CGRect(x: 1200, y: 24, width: 300, height: 400), number: 601)]
        XCTAssertTrue(popupGuard.defersCollapse())
    }

    func testStatusLevelPopoverAppearingAfterResetDefers() {
        let popupGuard = makeGuard()
        list.windows = [window(netMonitor, layer: status, CGRect(x: 1300, y: 0, width: 22, height: 24), number: 600)]
        popupGuard.reset()
        list.windows.append(window(netMonitor, layer: status, CGRect(x: 823, y: 26, width: 315, height: 93), number: 601))
        XCTAssertTrue(popupGuard.defersCollapse())
    }

    func testBaselineCoversTheGenericBranchToo() {
        let popupGuard = makeGuard()
        let panel = window(netMonitor, layer: 3, CGRect(x: 1250, y: 28, width: 320, height: 480), number: 700)
        list.windows = [panel]
        popupGuard.reset()
        XCTAssertFalse(popupGuard.defersCollapse())
    }

    func testFurnitureAndARealPopupTogetherDeferAndTheLogNamesThePopup() {
        displays = [notchDisplay]
        let popupGuard = makeGuard()
        let furniture = window(99, layer: status, notchWindow, number: 500)
        list.windows = [furniture]
        popupGuard.reset()
        list.windows = [furniture, window(netMonitor, layer: popUpMenu, CGRect(x: 600, y: 24, width: 300, height: 300), number: 601)]
        XCTAssertTrue(popupGuard.defersCollapse())
        XCTAssertEqual(logged, ["AutoCollapse: holding for a popup from com.example.netmon at layer \(popUpMenu)"])
    }

    func testStatusItemWindowsInTheBaselineStillNameTheirOwner() {
        owners = []
        let popupGuard = makeGuard()
        let item = window(documentApp, layer: status, CGRect(x: 1300, y: 0, width: 22, height: 24), number: 800)
        list.windows = [item]
        popupGuard.reset()
        list.windows = [item, window(documentApp, layer: 3, CGRect(x: 1180, y: 24, width: 260, height: 300), number: 801)]
        XCTAssertTrue(popupGuard.defersCollapse(), "the item is furniture but it still names the popup's owner")
    }

    func testASecondExpansionReadsTheBaselineAgain() {
        let popupGuard = makeGuard()
        list.windows = []
        popupGuard.reset()
        let late = window(netMonitor, layer: popUpMenu, CGRect(x: 1200, y: 24, width: 300, height: 400), number: 601)
        list.windows = [late]
        XCTAssertTrue(popupGuard.defersCollapse(), "new during the first expansion")

        popupGuard.reset()
        XCTAssertFalse(popupGuard.defersCollapse(), "still on screen when the second expansion began: furniture")
    }

    func testResetReadsTheWindowListOnceAndTheTimerOnceMore() {
        let popupGuard = makeGuard()
        popupGuard.reset()
        XCTAssertEqual(list.reads, 1)
        _ = popupGuard.defersCollapse()
        XCTAssertEqual(list.reads, 2)
    }

    // The panel and the banner share one long-lived window; the baseline must
    // not hide the panel.
    func testTallNotificationCenterWindowPresentAtResetStillFollowsThePanel() {
        let popupGuard = makeGuard()
        list.windows = [window(notificationCenter, layer: 23, CGRect(x: 0, y: 0, width: 1600, height: 900), number: 900)]
        popupGuard.reset()
        panelOpen = true
        XCTAssertTrue(popupGuard.defersCollapse())
        panelOpen = false
        XCTAssertFalse(popupGuard.defersCollapse())
    }

    // No reset yet: every window counts, as before the baseline existed.
    func testWithoutAResetNothingIsExcluded() {
        displays = [notchDisplay]
        let popupGuard = makeGuard()
        list.windows = [window(netMonitor, layer: status, notchWindow, number: 500)]
        XCTAssertTrue(popupGuard.defersCollapse())
    }

    // macOS may reuse one window for Control Center's panel, so Apple's windows
    // never count as furniture.
    func testAppleWindowPresentAtResetStillDefers() {
        let popupGuard = makeGuard()
        list.windows = [window(controlCenter, layer: popUpMenu, CGRect(x: 1200, y: 0, width: 300, height: 400))]
        popupGuard.reset()
        XCTAssertTrue(popupGuard.defersCollapse())
    }

    func testThirdPartyStatusWindowPresentAtResetDoesNotDefer() {
        displays = [notchDisplay]
        let popupGuard = makeGuard()
        list.windows = [window(netMonitor, layer: status, notchWindow)]
        popupGuard.reset()
        XCTAssertFalse(popupGuard.defersCollapse())
    }

    func testWindowWithNoBundleIdentifierPresentAtResetDoesNotDefer() {
        displays = [notchDisplay]
        let popupGuard = makeGuard()
        list.windows = [window(99, layer: status, notchWindow)]
        popupGuard.reset()
        XCTAssertFalse(popupGuard.defersCollapse())
    }
}
