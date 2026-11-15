//
//  RevealControllerTests.swift
//  HiddenBarTests
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import AppKit
import XCTest

/// Contract: monitors exist only while their pref is on; a recognised gesture
/// shows or hides the bar through the host; the edge states stay quiet.
/// Serves: RevealController.
/// Mock boundary: the event monitors, the host and the Accessibility read are
/// fakes; the detectors and policy are the real ones.
final class RevealControllerTests: XCTestCase {

    private final class FakeMonitoring: RevealEventMonitoring {
        private(set) var live: [Int: NSEvent.EventTypeMask] = [:]
        private(set) var added: [NSEvent.EventTypeMask] = []
        private var next = 0
        func addGlobalMonitor(matching mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> Void) -> Any? {
            next += 1
            live[next] = mask
            added.append(mask)
            return next
        }
        func removeMonitor(_ token: Any) { live[token as! Int] = nil }
        var liveMasks: [NSEvent.EventTypeMask] { live.values.map { $0 } }
    }

    private final class World {
        var collapsed = true
        var ownMenuOpen = false
        var enabled: Set<RevealTrigger> = []
        var shown = 0, hidden = 0, hiddenOffBar = 0
        var presenting = false
        var canHitTest = true
        var hitTarget = HitTarget.emptySpace
        var hitTests = 0
        let monitoring = FakeMonitoring()
        var screens = [ScreenBand(frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                  visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 876),
                                  notchGap: 660...780)]
        let barPoint = CGPoint(x: 300, y: 890)
        let offBarPoint = CGPoint(x: 300, y: 400)

        lazy var controller = RevealController(
            host: RevealHost(
                isCollapsed: { [unowned self] in self.collapsed },
                isOwnMenuOpen: { [unowned self] in self.ownMenuOpen },
                show: { [unowned self] in self.shown += 1; self.collapsed = false },
                hide: { [unowned self] in self.hidden += 1; self.collapsed = true },
                hideOffMenuBar: { [unowned self] in self.hiddenOffBar += 1; self.collapsed = true }),
            isEnabled: { [unowned self] in self.enabled.contains($0) },
            isSuspended: { [unowned self] in self.presenting },
            screens: { [unowned self] in self.screens },
            monitoring: monitoring,
            canHitTest: { [unowned self] in self.canHitTest },
            hitTest: { [unowned self] _, done in self.hitTests += 1; done(self.hitTarget) })
    }

    private let world = World()
    private var controller: RevealController { world.controller }

    private func scrollDown(at point: CGPoint? = nil, time: TimeInterval = 100) {
        controller.ingestScroll(deltaY: -20, time: time, isMomentum: false, at: point ?? world.barPoint)
    }

    // MARK: monitors follow the prefs

    // Given every pref off
    // When syncing
    // Then no monitor exists
    func test_noMonitorsWhileEverythingIsOff() {
        controller.sync()
        XCTAssertTrue(world.monitoring.added.isEmpty)
    }

    // Given each pref in turn
    // When it is on, then off again
    // Then exactly its own monitor comes and goes, and no key event is ever watched
    func test_eachPrefOwnsItsMonitor() {
        let cases: [(RevealTrigger, NSEvent.EventTypeMask)] = [(.scroll, .scrollWheel), (.shake, .mouseMoved), (.click, .leftMouseDown)]
        for (trigger, mask) in cases {
            world.enabled = [trigger]
            controller.sync()
            XCTAssertEqual(world.monitoring.liveMasks, [mask], "\(trigger)")
            world.enabled = []
            controller.sync()
            XCTAssertTrue(world.monitoring.liveMasks.isEmpty, "\(trigger) monitor stayed")
        }
        let keyMasks: NSEvent.EventTypeMask = [.keyDown, .keyUp, .flagsChanged]
        XCTAssertTrue(world.monitoring.added.allSatisfy { $0.intersection(keyMasks).isEmpty })
    }

    func test_syncTwice_installsOnce() {
        world.enabled = [.scroll]
        controller.sync()
        controller.sync()
        XCTAssertEqual(world.monitoring.added.count, 1)
    }

    // Given a scroll reveal with the click pref off
    // When the icons are out
    // Then a mouse-down monitor exists to hide them again, and goes when they collapse
    func test_mouseDownMonitor_livesWhileGestureIconsAreOut() {
        world.enabled = [.scroll]
        controller.sync()
        scrollDown()
        XCTAssertTrue(world.monitoring.liveMasks.contains(.leftMouseDown))
        controller.barDidCollapse()
        XCTAssertFalse(world.monitoring.liveMasks.contains(.leftMouseDown))
    }

    // MARK: scroll

    func test_scrollDownOnBar_showsAndCounts() {
        world.enabled = [.scroll]
        scrollDown()
        XCTAssertEqual(world.shown, 1)
        XCTAssertEqual(controller.triggerCounts[.scroll], 1)
        XCTAssertTrue(controller.revealedByGesture)
    }

    func test_scrollWithPrefOff_doesNothing() {
        scrollDown()
        XCTAssertEqual(world.shown, 0)
    }

    // Given a scroll below the menu bar
    // When it crosses the threshold
    // Then the bar stays collapsed
    func test_scrollOffTheBar_doesNothing() {
        world.enabled = [.scroll]
        scrollDown(at: world.offBarPoint)
        XCTAssertEqual(world.shown, 0)
    }

    // Given a scroll over another app's icon
    // When it crosses the threshold
    // Then the icon keeps it and Hidden Bar stays quiet
    func test_scrollOverIcon_isLeftToTheIcon() {
        world.enabled = [.scroll]
        world.hitTarget = .statusItem
        scrollDown()
        XCTAssertEqual(world.shown, 0)
    }

    // Given no Accessibility (the App Store build)
    // When scrolling the bar
    // Then it still reveals, since no hit test is possible
    func test_scrollWithoutAccessibility_stillReveals() {
        world.enabled = [.scroll]
        world.canHitTest = false
        scrollDown()
        XCTAssertEqual(world.shown, 1)
        XCTAssertEqual(world.hitTests, 0)
    }

    // Given the bar already expanded
    // When scrolling down
    // Then nothing changes
    func test_scrollDownWhenExpanded_doesNothing() {
        world.enabled = [.scroll]
        world.collapsed = false
        scrollDown()
        XCTAssertEqual(world.shown, 0)
        XCTAssertFalse(controller.revealedByGesture)
    }

    // Given the icons out
    // When scrolling up
    // Then they hide
    func test_scrollUp_hides() {
        world.enabled = [.scroll]
        world.collapsed = false
        controller.ingestScroll(deltaY: 20, time: 100, isMomentum: false, at: world.barPoint)
        XCTAssertEqual(world.hidden, 1)
    }

    // Given Hidden Bar's own menu open
    // When any gesture fires
    // Then nothing happens
    func test_ownMenuOpen_blocksGestures() {
        world.enabled = [.scroll, .click, .shake]
        world.ownMenuOpen = true
        scrollDown()
        controller.ingestMouseDown(at: world.barPoint)
        XCTAssertEqual(world.shown, 0)
    }

    // MARK: click

    func test_clickOnEmptySpace_reveals() {
        world.enabled = [.click]
        controller.ingestMouseDown(at: world.barPoint)
        XCTAssertEqual(world.shown, 1)
        XCTAssertEqual(controller.triggerCounts[.click], 1)
    }

    // Given a click on an icon, on a menu title, or where Accessibility says nothing
    // When the click lands
    // Then it is ignored
    func test_clickOnItemOrTitleOrUnknown_isIgnored() {
        world.enabled = [.click]
        for target in [HitTarget.statusItem, .menuTitle, .unknown] {
            world.hitTarget = target
            controller.ingestMouseDown(at: world.barPoint)
        }
        XCTAssertEqual(world.shown, 0)
    }

    // Given no Accessibility
    // When clicking the bar
    // Then nothing reveals, because empty space cannot be told from an icon
    func test_clickWithoutAccessibility_doesNothing() {
        world.enabled = [.click]
        world.canHitTest = false
        controller.ingestMouseDown(at: world.barPoint)
        XCTAssertEqual(world.shown, 0)
    }

    // Given a click inside the camera notch
    // When it lands
    // Then it is ignored
    func test_clickInNotch_isIgnored() {
        world.enabled = [.click]
        controller.ingestMouseDown(at: CGPoint(x: 700, y: 890))
        XCTAssertEqual(world.shown, 0)
    }

    // MARK: shake

    private func shake(at y: CGFloat? = nil) {
        let y = y ?? world.barPoint.y
        for (index, x) in [100, 140, 100, 140, 100].enumerated() {
            controller.ingestMouseMoved(at: CGPoint(x: CGFloat(x), y: y), time: 50 + Double(index) * 0.1)
        }
    }

    func test_shakeInBar_reveals() {
        world.enabled = [.shake]
        shake()
        XCTAssertEqual(world.shown, 1)
        XCTAssertEqual(controller.triggerCounts[.shake], 1)
    }

    // Given a full-screen app (no band) or a shake below the bar
    // When the pointer swings
    // Then it never reveals
    func test_shakeOutsideBand_doesNothing() {
        world.enabled = [.shake]
        shake(at: 400)
        world.screens = [ScreenBand(frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                    visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), notchGap: nil)]
        shake(at: 899)
        XCTAssertEqual(world.shown, 0)
    }

    // MARK: presentation mode

    // Given every gesture on, and presentation mode on
    // When each gesture fires (scroll down, scroll up, an empty click, a shake)
    // Then nothing shows or hides and nothing is counted; with the mode off they work again
    func test_gesturesDoNothingWhilePresenting() {
        world.enabled = [.scroll, .click, .shake]
        world.presenting = true
        scrollDown()
        controller.ingestMouseDown(at: world.barPoint)
        shake()
        world.collapsed = false
        controller.ingestScroll(deltaY: 20, time: 200, isMomentum: false, at: world.barPoint)
        XCTAssertEqual(world.shown, 0)
        XCTAssertEqual(world.hidden, 0)
        XCTAssertTrue(controller.triggerCounts.isEmpty)
        XCTAssertFalse(controller.revealedByGesture)

        world.presenting = false
        world.collapsed = true
        controller.ingestMouseDown(at: world.barPoint)
        XCTAssertEqual(world.shown, 1)
    }

    // MARK: hide again

    // Given icons revealed by a gesture
    // When clicking off the menu bar
    // Then they hide through the off-bar path
    func test_clickOffBar_hidesWhatAGestureRevealed() {
        world.enabled = [.scroll]
        scrollDown()
        controller.ingestMouseDown(at: world.offBarPoint)
        XCTAssertEqual(world.hiddenOffBar, 1)
        XCTAssertTrue(world.collapsed)
    }

    // Given icons the user opened with the arrow
    // When clicking off the menu bar
    // Then they stay: only gesture reveals hide on an off-bar click
    func test_clickOffBar_leavesArrowExpansionAlone() {
        world.enabled = [.click]
        world.collapsed = false
        controller.ingestMouseDown(at: world.offBarPoint)
        XCTAssertEqual(world.hiddenOffBar, 0)
    }

    // Given icons revealed by a gesture that the auto-hide timer already collapsed
    // When clicking off the bar
    // Then nothing is hidden twice and the gesture state clears
    func test_clickOffBar_afterCollapse_clearsState() {
        world.enabled = [.scroll]
        scrollDown()
        world.collapsed = true
        controller.ingestMouseDown(at: world.offBarPoint)
        XCTAssertEqual(world.hiddenOffBar, 0)
        XCTAssertFalse(controller.revealedByGesture)
    }

    // MARK: debug hook

    // Given each pref on
    // When the debug hook simulates each gesture
    // Then it runs the same path as a real event: the bar shows and the count rises
    func test_simulate_drivesTheRealPath() {
        world.enabled = [.scroll, .click, .shake]
        for gesture in ["scroll", "click", "shake"] {
            world.collapsed = true
            controller.simulate(gesture, now: 1000)
        }
        XCTAssertEqual(world.shown, 3)
        for trigger in RevealTrigger.allCases {
            XCTAssertEqual(controller.triggerCounts[trigger], 1, "\(trigger)")
        }
    }

    func test_simulate_respectsThePref() {
        controller.simulate("scroll", now: 1000)
        controller.simulate("click", now: 1000)
        controller.simulate("shake", now: 1000)
        XCTAssertEqual(world.shown, 0)
    }
}
