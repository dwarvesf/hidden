//
//  NoHideNoticeTests.swift
//  HiddenTests
//
//  Copyright © 2026 Console Labs. All rights reserved.
//

import XCTest
import AppKit
@testable import Hidden_Bar

/// Contract: a reason a click hid nothing maps to one short text and at most one
/// button, and a notice is shown only for a manual request, once per reason per
/// launch, never over another notice. Texts compare through `.localized`, so the
/// test holds in any language the host runs in.
/// Mock boundary: none. Pure values, plus the notice view built offscreen.
final class NoHideNoticeTests: XCTestCase {

    // MARK: policy

    func testManualRequestShowsOnce() {
        var policy = NoHideNoticePolicy()
        XCTAssertTrue(policy.shouldShow(.outsideApplications, userInitiated: true, isNoticeShowing: false))
        policy.recordShown(.outsideApplications)
        XCTAssertFalse(policy.shouldShow(.outsideApplications, userInitiated: true, isNoticeShowing: false))
        XCTAssertTrue(policy.shouldShow(.accessibilityNeeded, userInitiated: true, isNoticeShowing: false),
                      "each reason has its own turn")
    }

    func testAutomaticRequestNeverShows() {
        let policy = NoHideNoticePolicy()
        for reason: NoHideReason in [.outsideApplications, .unkeepableIcons(names: ["A"]), .accessibilityNeeded, .everythingRightOfArrow] {
            XCTAssertFalse(policy.shouldShow(reason, userInitiated: false, isNoticeShowing: false), "\(reason)")
        }
    }

    func testNoticeAlreadyShowingBlocksAnotherWithoutSpendingTheReason() {
        var policy = NoHideNoticePolicy()
        XCTAssertFalse(policy.shouldShow(.everythingRightOfArrow, userInitiated: true, isNoticeShowing: true))
        XCTAssertTrue(policy.shouldShow(.everythingRightOfArrow, userInitiated: true, isNoticeShowing: false))
        policy.recordShown(.unkeepableIcons(names: ["A"]))
        XCTAssertFalse(policy.shouldShow(.unkeepableIcons(names: ["B"]), userInitiated: true, isNoticeShowing: false),
                       "other names do not make it a new reason")
    }

    // MARK: texts

    func testOutsideApplicationsReusesTheStatusCardAndOffersTheMove() {
        let model = NoHideNoticeModel.make(.outsideApplications, runningFolder: "Downloads")
        XCTAssertEqual(model.title, "Move Hidden Bar to Applications".localized)
        XCTAssertEqual(model.text, String(format: "It is running from %@. macOS 27 hides icons only for apps in the Applications folder, so nothing is hidden yet.".localized, "Downloads"))
        XCTAssertEqual(model.action, .moveToApplications)
        XCTAssertEqual(model.buttonTitle, "Move to Applications".localized)
    }

    func testUnkeepableIconsNameTheAppsAndOpenAdvancedSettings() {
        let model = NoHideNoticeModel.make(.unkeepableIcons(names: ["JamfDaemon", "JetBrains"]), runningFolder: "")
        XCTAssertTrue(model.text.contains("JamfDaemon"))
        XCTAssertTrue(model.text.contains("JetBrains"))
        XCTAssertEqual(model.action, .openSettings(.advanced))
        XCTAssertEqual(model.buttonTitle, "Open Settings…".localized)
    }

    func testUnkeepableIconsWithoutNamesStillReadAsASentence() {
        let model = NoHideNoticeModel.make(.unkeepableIcons(names: []), runningFolder: "")
        XCTAssertTrue(model.text.contains("icons with no name".localized))
    }

    func testAccessibilityNeededOpensSettings() {
        let model = NoHideNoticeModel.make(.accessibilityNeeded, runningFolder: "")
        XCTAssertEqual(model.title, "Hidden Bar needs Accessibility access".localized)
        XCTAssertEqual(model.action, .openSettings(.general))
    }

    func testNothingToHideTellsHowToDragAndHasNoButton() {
        let model = NoHideNoticeModel.make(.everythingRightOfArrow, runningFolder: "")
        XCTAssertEqual(model.text, "Every icon is right of the arrow, so there is nothing to hide. Hold Command and drag the arrow to the right of the icons you want to hide.".localized)
        XCTAssertNil(model.action)
        XCTAssertNil(model.buttonTitle)
    }

    #if HIDDENBAR_NATIVE_VISIBILITY

    // MARK: view

    private func buttons(in view: NSView) -> [NSButton] {
        view.subviews.flatMap { sub -> [NSButton] in
            (sub as? NSButton).map { [$0] } ?? buttons(in: sub)
        }
    }

    func testViewPutsOneButtonOnAnActionNoticeAndRunsIt() {
        let view = NoHideNoticeView(model: NoHideNoticeModel.make(.accessibilityNeeded, runningFolder: ""))
        var ran = 0
        view.onAction = { ran += 1 }
        let found = buttons(in: view)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.identifier?.rawValue, NoHideNoticeView.buttonIdentifier)
        found.first?.performClick(nil)
        XCTAssertEqual(ran, 1)
        XCTAssertEqual(view.fittingSize.width, NoHideNoticeView.width)
    }

    func testViewHasNoButtonWhenThereIsNothingToDo() {
        let view = NoHideNoticeView(model: NoHideNoticeModel.make(.everythingRightOfArrow, runningFolder: ""))
        XCTAssertTrue(buttons(in: view).isEmpty)
    }

    // The collapse answers before the bar has reflowed, so the popover is
    // anchored on the next run loop turn, from the arrow's frame then.
    func testPresenterAnchorsOnTheNextTurnNotDuringTheCollapse() {
        var anchored = 0
        let presenter = ArrowNoticePresenter(perform: { _ in }, showPopover: { _, _ in anchored += 1 }, isOnScreen: { _ in true })
        let button = NSStatusBarButton()
        XCTAssertTrue(presenter.show(.everythingRightOfArrow, from: button))
        XCTAssertEqual(anchored, 0, "nothing is placed while the answer is still being delivered")
        XCTAssertTrue(presenter.isShown, "a second notice must not stack while this one waits")
        XCTAssertFalse(presenter.show(.accessibilityNeeded, from: button))
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(anchored, 1)
    }

    func testPresenterShowsNothingWhenTheArrowLeftTheScreenMeanwhile() {
        var anchored = 0
        var onScreen = true
        let presenter = ArrowNoticePresenter(perform: { _ in }, showPopover: { _, _ in anchored += 1 }, isOnScreen: { _ in onScreen })
        let button = NSStatusBarButton()
        XCTAssertTrue(presenter.show(.everythingRightOfArrow, from: button))
        onScreen = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(anchored, 0)
        XCTAssertFalse(presenter.isShown, "a notice that never appeared must not block the next one")
    }

    func testPresenterDeclinesWithoutAnArrowOnScreen() {
        var popovers = 0
        let presenter = ArrowNoticePresenter(perform: { _ in }, showPopover: { _, _ in popovers += 1 })
        XCTAssertFalse(presenter.show(.everythingRightOfArrow, from: nil))
        XCTAssertEqual(popovers, 0)
        XCTAssertFalse(presenter.isShown)
    }

    #endif
}
