//
//  RevealGesturesTests.swift
//  HiddenBarTests
//
//  Copyright © 2026 Console Labs. All rights reserved.
//

import CoreGraphics
import XCTest

/// Contract: the pure rules behind scroll, click and shake reveal.
/// Serves: RevealGestures.swift.
/// Mock boundary: none; every type is plain data.
final class RevealGesturesTests: XCTestCase {

    // MARK: scroll

    // Given a detector
    // When content scrolls up past the threshold, in small steps
    // Then it asks to show exactly once, on the step that crosses
    func test_scrollDown_showsOnceWhenThresholdCrossed() {
        var detector = ScrollRevealDetector()
        var actions: [ScrollRevealAction?] = []
        for index in 0..<6 {
            actions.append(detector.feed(deltaY: -2, at: Double(index) * 0.01))
        }
        XCTAssertEqual(actions, [nil, nil, nil, .show, nil, nil])
    }

    func test_scrollUp_hidesWhenThresholdCrossed() {
        var detector = ScrollRevealDetector()
        XCTAssertNil(detector.feed(deltaY: 5, at: 0))
        XCTAssertEqual(detector.feed(deltaY: 5, at: 0.01), .hide)
    }

    // Given a scroll too short to cross the threshold
    // When it ends
    // Then nothing fires
    func test_smallScroll_doesNothing() {
        var detector = ScrollRevealDetector()
        XCTAssertNil(detector.feed(deltaY: -3, at: 0))
        XCTAssertNil(detector.feed(deltaY: -3, at: 0.01))
    }

    // Given one scroll gesture that already fired
    // When more events of the same gesture arrive
    // Then none fires again until a quiet gap
    func test_oneFirePerGesture_untilQuietGap() {
        var detector = ScrollRevealDetector()
        XCTAssertEqual(detector.feed(deltaY: -20, at: 0), .show)
        XCTAssertNil(detector.feed(deltaY: -20, at: 0.1))
        XCTAssertNil(detector.feed(deltaY: -20, at: 0.2))
        XCTAssertEqual(detector.feed(deltaY: -20, at: 0.2 + RevealTuning.scrollQuietGap + 0.01), .show)
    }

    // Given a gesture that fired
    // When momentum events follow the lifted fingers
    // Then they are ignored, so the glide does not start a second gesture
    func test_momentumEvents_areIgnored() {
        var detector = ScrollRevealDetector()
        XCTAssertEqual(detector.feed(deltaY: -20, at: 0), .show)
        XCTAssertNil(detector.feed(deltaY: -20, at: 1, isMomentum: true))
        XCTAssertNil(detector.feed(deltaY: -20, at: 1.5, isMomentum: true))
    }

    // Given a scroll up that has not crossed yet
    // When the direction flips to down
    // Then the old travel is dropped; only the new direction adds up
    func test_directionChange_dropsOldTravel() {
        var detector = ScrollRevealDetector()
        XCTAssertNil(detector.feed(deltaY: 6, at: 0))
        XCTAssertNil(detector.feed(deltaY: -6, at: 0.01))
        XCTAssertEqual(detector.feed(deltaY: -6, at: 0.02), .show)
    }

    func test_scrollWithZeroDelta_doesNothing() {
        var detector = ScrollRevealDetector()
        XCTAssertNil(detector.feed(deltaY: 0, at: 0))
    }

    // MARK: shake

    private func shake(_ detector: inout ShakeDetector, xs: [CGFloat], step: TimeInterval, start: TimeInterval = 10) -> [Bool] {
        xs.enumerated().map { detector.feed(x: $1, at: start + Double($0) * step, inBand: true) }
    }

    // Given a detector
    // When the pointer swings wide, left and right, three reversals in 0.4 s
    // Then it fires on the third reversal and not before
    func test_shake_firesOnThirdReversal() {
        var detector = ShakeDetector()
        let fired = shake(&detector, xs: [100, 140, 100, 140, 100], step: 0.1)
        XCTAssertEqual(fired, [false, false, false, false, true])
    }

    // Given the same swings
    // When they are spread over more than the window
    // Then it never fires
    func test_slowShake_doesNotFire() {
        var detector = ShakeDetector()
        let fired = shake(&detector, xs: [100, 140, 100, 140, 100, 140, 100], step: 0.4)
        XCTAssertFalse(fired.contains(true))
    }

    // Given swings narrower than the minimum
    // When the pointer jitters
    // Then it never fires
    func test_jitter_doesNotFire() {
        var detector = ShakeDetector()
        let fired = shake(&detector, xs: [100, 106, 100, 106, 100, 106, 100, 106], step: 0.05)
        XCTAssertFalse(fired.contains(true))
    }

    // Given a shake in progress
    // When the pointer leaves the menu bar band
    // Then the count starts over
    func test_leavingBand_resetsShake() {
        var detector = ShakeDetector()
        _ = shake(&detector, xs: [100, 140, 100], step: 0.05)
        XCTAssertFalse(detector.feed(x: 140, at: 10.2, inBand: false))
        let fired = shake(&detector, xs: [140, 100], step: 0.05, start: 10.3)
        XCTAssertEqual(fired, [false, false])
    }

    // Given a shake that fired
    // When the pointer keeps swinging
    // Then it stays quiet for the cooldown, then can fire again
    func test_shake_cooldownThenAgain() {
        var detector = ShakeDetector()
        XCTAssertTrue(shake(&detector, xs: [100, 140, 100, 140, 100], step: 0.1).last ?? false)
        let during = shake(&detector, xs: [140, 100, 140, 100, 140], step: 0.05, start: 10.5)
        XCTAssertFalse(during.contains(true))
        let after = shake(&detector, xs: [100, 140, 100, 140, 100], step: 0.1, start: 10.4 + RevealTuning.shakeCooldown + 0.1)
        XCTAssertTrue(after.last ?? false)
    }

    // MARK: menu bar band

    private let primary = ScreenBand(frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                     visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 876), notchGap: nil)
    private let secondary = ScreenBand(frame: CGRect(x: 1440, y: 100, width: 1920, height: 1080),
                                       visibleFrame: CGRect(x: 1440, y: 100, width: 1920, height: 1056), notchGap: nil)
    private let fullScreen = ScreenBand(frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                        visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), notchGap: nil)

    func test_band_isTheStripAboveTheVisibleFrame() {
        XCTAssertTrue(MenuBarBand.contains(CGPoint(x: 700, y: 890), in: [primary]))
        XCTAssertFalse(MenuBarBand.contains(CGPoint(x: 700, y: 500), in: [primary]))
        XCTAssertFalse(MenuBarBand.contains(CGPoint(x: 1700, y: 890), in: [primary]))
    }

    // Given two displays
    // When the pointer is on the second one's bar
    // Then it counts, so a gesture works on any screen
    func test_band_countsOnAnyScreen() {
        XCTAssertTrue(MenuBarBand.contains(CGPoint(x: 2000, y: 1170), in: [primary, secondary]))
    }

    // Given a full-screen app that hides the bar
    // When the pointer is at the top
    // Then there is no band, so shake and scroll stay quiet
    func test_fullScreen_hasNoBand() {
        XCTAssertNil(fullScreen.rect)
        XCTAssertFalse(MenuBarBand.contains(CGPoint(x: 700, y: 899), in: [fullScreen]))
    }

    // Given a notched screen
    // When a click lands between the camera's two sides
    // Then it is in the notch, not on usable bar
    func test_notchGap() {
        let notched = ScreenBand(frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                 visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 945), notchGap: 660...852)
        XCTAssertTrue(MenuBarBand.isInNotch(CGPoint(x: 756, y: 970), in: [notched]))
        XCTAssertFalse(MenuBarBand.isInNotch(CGPoint(x: 300, y: 970), in: [notched]))
        XCTAssertFalse(MenuBarBand.isInNotch(CGPoint(x: 756, y: 500), in: [notched]))
    }

    func test_accessibilityPoint_flipsY() {
        XCTAssertEqual(MenuBarBand.accessibilityPoint(fromAppKit: CGPoint(x: 10, y: 890), primaryScreenHeight: 900),
                       CGPoint(x: 10, y: 10))
    }

    // MARK: classification and policy

    func test_classifier() {
        XCTAssertEqual(HitClassifier.target(for: HitProbe(role: "AXMenuBar", ownerPID: 5, frontmostPID: 5, menuBarOwnerPID: 5)), .emptySpace)
        XCTAssertEqual(HitClassifier.target(for: HitProbe(role: "AXMenuBarItem", ownerPID: 5, frontmostPID: 5, menuBarOwnerPID: 5)), .menuTitle)
        XCTAssertEqual(HitClassifier.target(for: HitProbe(role: "AXMenuBarItem", ownerPID: 9, frontmostPID: 5, menuBarOwnerPID: 5)), .statusItem)
        XCTAssertEqual(HitClassifier.target(for: HitProbe(role: "AXMenuExtra", ownerPID: nil, frontmostPID: 5, menuBarOwnerPID: 5)), .statusItem)
        XCTAssertEqual(HitClassifier.target(for: HitProbe(role: "AXGroup", ownerPID: 5, frontmostPID: 5)), .unknown)
        XCTAssertEqual(HitClassifier.target(for: HitProbe(role: nil, ownerPID: nil, frontmostPID: nil)), .unknown)
    }

    // Given a frontmost app with no menus (A) while another app (B) owns the menu bar
    // When the hit is a menu bar item owned by B, or by A
    // Then B's item is a menu title and A's is an icon
    func test_menuTitleBelongsToTheMenuBarOwner_notTheFrontmostApp() {
        let titleOfB = HitProbe(role: "AXMenuBarItem", ownerPID: 7, frontmostPID: 5, menuBarOwnerPID: 7)
        XCTAssertEqual(HitClassifier.target(for: titleOfB), .menuTitle)
        let itemOfA = HitProbe(role: "AXMenuBarItem", ownerPID: 5, frontmostPID: 5, menuBarOwnerPID: 7)
        XCTAssertEqual(HitClassifier.target(for: itemOfA), .statusItem)
    }

    // Given each gesture and each thing under the pointer
    // When asking whether it may show the icons
    // Then a click needs empty space, a scroll yields to icons, a shake always counts
    func test_policy_showRules() {
        func allows(_ trigger: RevealTrigger, _ target: HitTarget, collapsed: Bool = true, menu: Bool = false) -> Bool {
            RevealPolicy.allowsShow(trigger, target: target, barIsCollapsed: collapsed, ownMenuIsOpen: menu)
        }
        XCTAssertTrue(allows(.click, .emptySpace))
        XCTAssertFalse(allows(.click, .menuTitle))
        XCTAssertFalse(allows(.click, .statusItem))
        XCTAssertFalse(allows(.click, .unknown))
        XCTAssertTrue(allows(.scroll, .emptySpace))
        XCTAssertTrue(allows(.scroll, .menuTitle))
        XCTAssertTrue(allows(.scroll, .unknown))
        XCTAssertFalse(allows(.scroll, .statusItem))
        XCTAssertTrue(allows(.shake, .unknown))
        for trigger in RevealTrigger.allCases {
            XCTAssertFalse(allows(trigger, .emptySpace, collapsed: false), "\(trigger) acts on a bar that is already expanded")
            XCTAssertFalse(allows(trigger, .emptySpace, menu: true), "\(trigger) acts while Hidden Bar's menu is open")
        }
    }

    func test_policy_scrollHide() {
        XCTAssertTrue(RevealPolicy.allowsScrollHide(target: .emptySpace, barIsCollapsed: false, ownMenuIsOpen: false))
        XCTAssertFalse(RevealPolicy.allowsScrollHide(target: .statusItem, barIsCollapsed: false, ownMenuIsOpen: false))
        XCTAssertFalse(RevealPolicy.allowsScrollHide(target: .emptySpace, barIsCollapsed: true, ownMenuIsOpen: false))
        XCTAssertFalse(RevealPolicy.allowsScrollHide(target: .emptySpace, barIsCollapsed: false, ownMenuIsOpen: true))
    }

    func test_policy_offBarHide() {
        XCTAssertTrue(RevealPolicy.allowsOffBarHide(clickIsInMenuBar: false, revealedByGesture: true, barIsCollapsed: false, ownMenuIsOpen: false))
        XCTAssertFalse(RevealPolicy.allowsOffBarHide(clickIsInMenuBar: true, revealedByGesture: true, barIsCollapsed: false, ownMenuIsOpen: false))
        XCTAssertFalse(RevealPolicy.allowsOffBarHide(clickIsInMenuBar: false, revealedByGesture: false, barIsCollapsed: false, ownMenuIsOpen: false))
        XCTAssertFalse(RevealPolicy.allowsOffBarHide(clickIsInMenuBar: false, revealedByGesture: true, barIsCollapsed: true, ownMenuIsOpen: false))
        XCTAssertFalse(RevealPolicy.allowsOffBarHide(clickIsInMenuBar: false, revealedByGesture: true, barIsCollapsed: false, ownMenuIsOpen: true))
    }
}
