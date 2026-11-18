//
//  PaletteRevealSessionTests.swift
//  HiddenBarTests
//
//  Copyright © 2026 Console Labs. All rights reserved.
//

import XCTest

/// Contract: Return allows one app, presses its icon, and puts the restriction
/// back once its menu or panel is gone; a bar the user changed meanwhile, an
/// icon that is missing or will not press, and an engine that cannot lift
/// one app all end cleanly.
/// Serves: PaletteRevealSession.
/// Mock boundary: the engine, the Accessibility press and the window list are
/// closures; time is a manual clock.
final class PaletteRevealSessionTests: XCTestCase {

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

    private var time: ManualTime!
    // What the session asked of the world, in order.
    private var log: [String] = []
    private var lift = PaletteLift.lifted
    private var allowCompletions: [(PaletteLift) -> Void] = []
    private var holdsAllow = false
    private var pressOutcomes: [PalettePressOutcome] = []
    private var menuOpen = false
    private var appActive = false
    private var results: [PaletteOpenResult] = []

    override func setUp() {
        super.setUp()
        time = ManualTime()
        log = []
        lift = .lifted
        allowCompletions = []
        holdsAllow = false
        pressOutcomes = [.pressed]
        menuOpen = false
        appActive = false
        results = []
    }

    private func makeSession() -> PaletteRevealSession {
        return PaletteRevealSession(
            now: { [unowned self] in time.now },
            after: { [unowned self] in time.after($0, $1) },
            allow: { [unowned self] bundle, done in
                log.append("allow \(bundle)")
                if holdsAllow { allowCompletions.append(done) } else { done(lift) }
            },
            press: { [unowned self] bundle, done in
                log.append("press \(bundle)")
                done(pressOutcomes.count > 1 ? pressOutcomes.removeFirst() : pressOutcomes[0])
            },
            menuIsOpen: { [unowned self] _ in menuOpen },
            appIsActive: { [unowned self] _ in appActive },
            restore: { [unowned self] in log.append("restore") })
    }

    private func open(_ session: PaletteRevealSession, _ bundle: String = "com.paste") {
        session.open(bundle: bundle) { [unowned self] in results.append($0) }
    }

    // MARK: the menu path

    // Given a hidden app
    // When Return opens it and its menu comes and goes
    // Then the app is allowed, its icon pressed, and the restriction put back only after the menu closed
    func test_allowPressWatchRestore() {
        let session = makeSession()
        open(session)
        XCTAssertEqual(log, ["allow com.paste"], "the icon is looked up after the lift has settled")
        XCTAssertTrue(session.isActive)

        time.advance(to: 0.06)
        XCTAssertEqual(log, ["allow com.paste", "press com.paste"])
        XCTAssertEqual(results, [.opened], "the palette can close as soon as the icon is pressed")

        menuOpen = true
        time.advance(to: 3)
        XCTAssertEqual(log.last, "press com.paste", "nothing is restored while the menu is up")
        XCTAssertTrue(session.isActive)

        menuOpen = false
        time.advance(to: 3.2)
        XCTAssertEqual(log, ["allow com.paste", "press com.paste", "restore"])
        XCTAssertFalse(session.isActive)
        XCTAssertEqual(session.lastEndReason, "menuClosed")
        XCTAssertEqual(results, [.opened], "reported once")
    }

    // Given an app that is shown already (the bar is expanded)
    // When Return opens it
    // Then it is pressed at once and nothing is restored afterwards
    func test_alreadyShown_pressesAtOnceAndRestoresNothing() {
        lift = .alreadyShown
        let session = makeSession()
        open(session)
        XCTAssertEqual(log, ["allow com.paste", "press com.paste"])
        menuOpen = true
        time.advance(to: 1)
        menuOpen = false
        time.advance(to: 2)
        XCTAssertEqual(log, ["allow com.paste", "press com.paste"])
        XCTAssertFalse(session.isActive)
    }

    // Given the user clicked the arrow while the menu was open
    // When the menu closes
    // Then the bar stays as the user left it: no restore
    func test_userChangedBar_keepsTheBarAsLeft() {
        let session = makeSession()
        open(session)
        time.advance(to: 0.06)
        menuOpen = true
        time.advance(to: 1)
        session.userChangedBar()
        menuOpen = false
        time.advance(to: 2)
        XCTAssertFalse(log.contains("restore"))
        XCTAssertFalse(session.isActive)
    }

    // Given a menu left open past the cap
    // When the cap passes
    // Then the app is hidden again like after a normal close, so it does not stay in a collapsed bar for ever
    func test_menuCap_putsTheRestrictionBack() {
        let session = makeSession()
        open(session)
        time.advance(to: 0.06)
        menuOpen = true
        time.advance(to: 700)
        XCTAssertFalse(session.isActive)
        XCTAssertEqual(session.lastEndReason, "menuCap")
        XCTAssertEqual(log, ["allow com.paste", "press com.paste", "restore"])
    }

    // Given the user changed the bar while a menu was open past the cap
    // When the cap passes
    // Then the bar stays as they left it
    func test_menuCap_keepsABarTheUserChanged() {
        let session = makeSession()
        open(session)
        time.advance(to: 0.06)
        menuOpen = true
        time.advance(to: 1)
        session.userChangedBar()
        time.advance(to: 700)
        XCTAssertEqual(session.lastEndReason, "menuCap")
        XCTAssertFalse(log.contains("restore"))
    }

    // MARK: apps that open a panel

    // Given an app that opens a panel, not a menu (Dropbox)
    // When the panel takes focus and later loses it
    // Then the restriction comes back at that point
    func test_panelApp_restoresWhenItLosesFocus() {
        let session = makeSession()
        open(session)
        time.advance(to: 0.06)
        appActive = true
        time.advance(to: 5)
        XCTAssertTrue(session.isActive, "the panel still has focus")
        appActive = false
        time.advance(to: 5.3)
        XCTAssertEqual(log.last, "restore")
        XCTAssertEqual(session.lastEndReason, "panelClosed")
    }

    // Given a panel that keeps focus for ever
    // When 15 seconds pass
    // Then the session ends and puts the restriction back
    func test_panelCap_putsTheRestrictionBackAfter15Seconds() {
        let session = makeSession()
        open(session)
        time.advance(to: 0.06)
        appActive = true
        time.advance(to: 14)
        XCTAssertTrue(session.isActive)
        time.advance(to: 16.2)
        XCTAssertFalse(session.isActive)
        XCTAssertEqual(session.lastEndReason, "panelCap")
        XCTAssertEqual(log, ["allow com.paste", "press com.paste", "restore"])
    }

    // Given a press that opened neither a menu nor a panel
    // When the grace period passes
    // Then the restriction comes back
    func test_nothingShown_restores() {
        let session = makeSession()
        open(session)
        time.advance(to: 4)
        XCTAssertFalse(session.isActive)
        XCTAssertEqual(session.lastEndReason, "nothingShown")
        XCTAssertEqual(log.last, "restore")
    }

    // MARK: failures

    // Given an app whose icon is not in the bar yet
    // When the icon appears within the timeout
    // Then the press is retried and succeeds
    func test_missingIcon_isRetriedUntilItAppears() {
        pressOutcomes = [.noItem, .noItem, .pressed]
        let session = makeSession()
        open(session)
        time.advance(to: 1)
        XCTAssertEqual(log.filter { $0 == "press com.paste" }.count, 3)
        XCTAssertEqual(results, [.opened])
        _ = session
    }

    // Given an app whose icon never appears
    // When the item timeout passes
    // Then the open fails with noItem and the restriction is back
    func test_noItem_failsAndRestores() {
        pressOutcomes = [.noItem]
        let session = makeSession()
        open(session)
        time.advance(to: 3)
        XCTAssertEqual(results, [.noItem])
        XCTAssertEqual(log.last, "restore")
        XCTAssertFalse(session.isActive)
    }

    // Given an icon that takes no Accessibility press
    // When Return opens it
    // Then the open fails with noPress, once, and the restriction is back
    func test_noPress_failsAndRestores() {
        pressOutcomes = [.noPress]
        let session = makeSession()
        open(session)
        time.advance(to: 1)
        XCTAssertEqual(results, [.noPress])
        XCTAssertEqual(log, ["allow com.paste", "press com.paste", "restore"])
        XCTAssertFalse(session.isActive)
    }

    // Given an engine that cannot lift one app
    // When Return opens it
    // Then it fails at once, presses nothing and restores nothing
    func test_unavailableEngine_failsWithoutPressing() {
        lift = .unavailable
        let session = makeSession()
        open(session)
        XCTAssertEqual(results, [.unavailable])
        XCTAssertEqual(log, ["allow com.paste"])
        XCTAssertFalse(session.isActive)
    }

    // Given an engine that keeps the app hidden for presentation mode
    // When Return opens it
    // Then the session ends as sensitive, presses nothing and restores nothing
    func test_sensitiveApp_endsWithoutPressing() {
        lift = .sensitive
        let session = makeSession()
        open(session)
        XCTAssertEqual(results, [.sensitive])
        XCTAssertEqual(log, ["allow com.paste"])
        XCTAssertFalse(session.isActive)
    }

    // Given an engine that never answers the allow
    // When the lift cap passes
    // Then the session gives up, so auto-collapse is not held back for ever
    func test_allowThatNeverAnswers_timesOut() {
        holdsAllow = true
        let session = makeSession()
        open(session)
        XCTAssertTrue(session.isActive)
        time.advance(to: 6)
        XCTAssertFalse(session.isActive)
        XCTAssertEqual(results, [.unavailable])
        allowCompletions.forEach { $0(.lifted) }
        XCTAssertEqual(log, ["allow com.paste", "restore"], "a late lift is put back, nothing is pressed")
    }

    // MARK: overlapping opens

    // Given an open still watching its menu
    // When a second app is opened
    // Then the first is put back before the second is allowed
    func test_aSecondOpen_restoresTheFirst() {
        let session = makeSession()
        open(session, "com.one")
        time.advance(to: 0.06)
        menuOpen = true
        time.advance(to: 0.5)
        open(session, "com.two")
        XCTAssertEqual(log, ["allow com.one", "press com.one", "restore", "allow com.two"])
        time.advance(to: 1.5)
        XCTAssertEqual(log.last, "press com.two")
    }
}
