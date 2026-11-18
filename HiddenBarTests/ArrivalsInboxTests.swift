//
//  ArrivalsInboxTests.swift
//  HiddenBarTests
//
//  Copyright © 2026 Console Labs. All rights reserved.
//

import XCTest

// The arrivals decisions: placement by the Settings default, the waiting queue,
// answers, the 24 hour lapse, and the upgrade rule. Fixtures only; the catalog's
// own diff is MenuBarCatalogStateTests.
final class ArrivalsInboxTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func place(_ bundle: String, _ section: MenuBarSection) -> ArrivalsInbox.Placement {
        ArrivalsInbox.Placement(bundle: bundle, section: section)
    }

    // MARK: Show It and Hide It

    // Given Show It, when an app arrives that the engine's resolver left on its read position (hidden)
    // Then nothing is written: the app stays hidden, exactly as 1.12 places it, and nothing is asked
    func test_showIt_leavesTheResolversPlacementAlone() {
        var inbox = ArrivalsInbox()
        let placements = inbox.receive(["com.a"], choice: .show, pinsSections: true, table: ["com.a": .hidden])

        XCTAssertEqual(placements, [])
        XCTAssertEqual(inbox.pending, [])
    }

    // Given Show It and an arrival the catalog never saw but the pinned table already holds
    //       (an App Store import, say), including one the user hid
    // Then the entry is left untouched
    func test_showIt_leavesAPinnedEntryTheCatalogNeverSawUntouched() {
        var inbox = ArrivalsInbox()
        let table: [String: MenuBarSection] = ["com.imported": .alwaysHidden, "com.other": .hidden]

        XCTAssertEqual(inbox.receive(["com.imported", "com.other"], choice: .show, pinsSections: true, table: table), [])
    }

    // Given Hide It, when an app arrives
    // Then it is placed hidden on first sight, and never asked
    func test_hideIt_placesHiddenAndNeverAsks() {
        var inbox = ArrivalsInbox()
        let placements = inbox.receive(["com.a", "com.b"], choice: .hide, pinsSections: true, table: ["com.a": .visible])

        XCTAssertEqual(placements, [place("com.a", .hidden), place("com.b", .hidden)])
        XCTAssertEqual(inbox.pending, [])
    }

    // MARK: Ask Me

    // Given Ask Me, when an app arrives that the table put on the hidden side
    // Then it is queued and written visible: it stays shown until the user answers
    func test_askMe_queuesAndKeepsTheAppShown() {
        var inbox = ArrivalsInbox()
        let placements = inbox.receive(["com.a"], choice: .ask, pinsSections: true, table: ["com.a": .hidden])

        XCTAssertEqual(inbox.pending, ["com.a"])
        XCTAssertEqual(placements, [place("com.a", .visible)])
    }

    // Given several apps found by one read
    // Then each waits, in the order given
    func test_severalArrivalsAtOnce_allWaitInOrder() {
        var inbox = ArrivalsInbox()
        _ = inbox.receive(["com.a", "com.b", "com.c"], choice: .ask, pinsSections: true, table: [:])

        XCTAssertEqual(inbox.pending, ["com.a", "com.b", "com.c"])
    }

    // Given a waiting app, when the answer is Hide
    // Then the app leaves the queue and the hidden section is returned for writing
    func test_answer_clearsTheEntryAndReturnsTheSection() {
        var inbox = ArrivalsInbox(pending: ["com.a", "com.b"])

        XCTAssertEqual(inbox.answer("com.a", .hide), place("com.a", .hidden))
        XCTAssertEqual(inbox.pending, ["com.b"])
        XCTAssertEqual(inbox.answer("com.b", .alwaysHide), place("com.b", .alwaysHidden))
        XCTAssertEqual(inbox.pending, [])
    }

    // Given an app that is not waiting, when an answer comes in (a stale prompt)
    // Then nothing is written
    func test_answerForAnAppNotWaiting_isIgnored() {
        var inbox = ArrivalsInbox(pending: ["com.a"])

        XCTAssertNil(inbox.answer("com.other", .hide))
        XCTAssertEqual(inbox.pending, ["com.a"])
    }

    // Given six waiting apps, when Hide All is pressed
    // Then every one is placed hidden and the queue is empty
    func test_answerAll_placesEveryWaitingApp() {
        var inbox = ArrivalsInbox(pending: ["com.a", "com.b", "com.c"])

        XCTAssertEqual(inbox.answerAll(.show), [place("com.a", .visible), place("com.b", .visible), place("com.c", .visible)])
        XCTAssertEqual(inbox.pending, [])
    }

    // MARK: asked at most once

    // Given an answered app, when the catalog publishes the same arrivals again
    //       (it repeats the latest read's list on every later publish)
    // Then the app is not queued again and the user's answer is not overwritten
    func test_anAnsweredAppIsNotAskedAgainInTheSameRun() {
        var inbox = ArrivalsInbox()
        _ = inbox.receive(["com.a"], choice: .ask, pinsSections: true, table: [:])
        _ = inbox.answer("com.a", .hide)

        let again = inbox.receive(["com.a"], choice: .ask, pinsSections: true, table: ["com.a": .hidden])
        XCTAssertEqual(again, [])
        XCTAssertEqual(inbox.pending, [])
    }

    // Given Hide It and an app the user then moved to visible
    // When the catalog repeats the arrival
    // Then the placement is not applied a second time
    func test_aRepeatedArrivalDoesNotUndoTheUsersEdit() {
        var inbox = ArrivalsInbox()
        _ = inbox.receive(["com.a"], choice: .hide, pinsSections: true, table: [:])

        XCTAssertEqual(inbox.receive(["com.a"], choice: .hide, pinsSections: true, table: ["com.a": .visible]), [])
    }

    // Given an answer and a restart
    // When the catalog (which persists first-seen times) reads the same bar
    // Then it announces nothing, so the new inbox asks nothing: the question is asked once, across restarts
    func test_anAppIsAskedAtMostOnce_acrossARestart() {
        var catalog = MenuBarCatalogState(firstSeen: nil)
        _ = catalog.apply(read: ["com.old": .visible], now: t0)
        var inbox = ArrivalsInbox()
        let arrivals = catalog.apply(read: ["com.old": .visible, "com.new": .visible], now: t0)
        _ = inbox.receive(arrivals, choice: .ask, pinsSections: true, table: [:])
        _ = inbox.answer("com.new", .show)

        // Launch again: the persisted first-seen map and the persisted queue come back.
        var relaunchedCatalog = MenuBarCatalogState(firstSeen: catalog.firstSeen)
        var relaunched = ArrivalsInbox(pending: inbox.pending)
        let found = relaunchedCatalog.apply(read: ["com.old": .visible, "com.new": .visible], now: t0)
        XCTAssertEqual(found, [])
        XCTAssertEqual(relaunched.receive(found, choice: .ask, pinsSections: true, table: [:]), [])
        XCTAssertEqual(relaunched.pending, [])
    }

    // Given a question not answered before a quit
    // When Hidden Bar starts again and the same app is injected or found
    // Then it is still waiting, once, and not queued a second time
    func test_aWaitingQuestionSurvivesARestart() {
        var inbox = ArrivalsInbox(pending: ["com.a"])
        inbox.inject("com.a")
        _ = inbox.receive(["com.a"], choice: .ask, pinsSections: true, table: ["com.a": .visible])

        XCTAssertEqual(inbox.pending, ["com.a"])
    }

    // MARK: edge states

    // Given an app that quits before it is answered
    // Then its entry stays (the icon returns with the app) until answered or removed
    func test_aQuitAppStaysWaitingUntilAnsweredOrRemovedFromTheList() {
        var inbox = ArrivalsInbox(pending: ["com.a", "com.b"])

        inbox.prune(keeping: ["com.a": .visible, "com.b": .visible])
        XCTAssertEqual(inbox.pending, ["com.a", "com.b"])

        inbox.prune(keeping: ["com.b": .visible])
        XCTAssertEqual(inbox.pending, ["com.b"])
    }

    // Given the upgrade run: the catalog has nothing persisted, the table holds the user's apps
    // Then the first read announces none of them, and only a later new app waits
    func test_upgrade_appsAlreadyOnTheBarAreNeverAsked() {
        var catalog = MenuBarCatalogState(firstSeen: nil)
        var inbox = ArrivalsInbox()

        let firstRun = catalog.apply(read: ["com.a": .visible, "com.b": .hidden], table: ["com.b": .hidden, "com.old": .alwaysHidden], now: t0)
        XCTAssertEqual(inbox.receive(firstRun, choice: .ask, pinsSections: true, table: ["com.b": .hidden]), [])
        XCTAssertEqual(inbox.pending, [])

        let later = catalog.apply(read: ["com.a": .visible, "com.b": .hidden, "com.new": .visible], now: t0 + 60)
        _ = inbox.receive(later, choice: .ask, pinsSections: true, table: [:])
        XCTAssertEqual(inbox.pending, ["com.new"])
    }

    // Given the beta off (the table is not applied)
    // Then nobody is placed or asked, and the arrival is not held for later
    func test_pinnedSectionsOff_placesAndAsksNothing() {
        var inbox = ArrivalsInbox()

        XCTAssertEqual(inbox.receive(["com.a"], choice: .ask, pinsSections: false, table: [:]), [])
        XCTAssertEqual(inbox.receive(["com.b"], choice: .hide, pinsSections: false, table: [:]), [])
        XCTAssertEqual(inbox.pending, [])
    }

    // Given macOS's own extras (Control Center draws them)
    // Then they are never asked about
    func test_macOSExtrasAreNeverAsked() {
        var inbox = ArrivalsInbox()

        XCTAssertEqual(inbox.receive([MenuBarLayoutResolver.systemExtrasBundle], choice: .ask, pinsSections: true, table: [:]), [])
        XCTAssertEqual(inbox.pending, [])
    }

    // MARK: lapse after 24 hours

    // Given a question under a day old
    // Then it keeps waiting
    func test_aQuestionUnderADayOldKeepsWaiting() {
        var inbox = ArrivalsInbox(pending: ["com.a"])
        let placements = inbox.expire(now: t0 + ArrivalsInbox.expiry - 1, firstSeen: { _ in self.t0 }, choice: .hide, table: ["com.a": .visible])

        XCTAssertEqual(placements, [])
        XCTAssertEqual(inbox.pending, ["com.a"])
    }

    // Given a question a day old and the default now Hide It
    // Then it lapses and the default is applied; under Ask Me the app simply stays shown
    func test_aLapsedQuestionTakesTheSettingsDefault() {
        var hide = ArrivalsInbox(pending: ["com.a"])
        XCTAssertEqual(hide.expire(now: t0 + ArrivalsInbox.expiry, firstSeen: { _ in self.t0 }, choice: .hide, table: ["com.a": .visible]),
                       [place("com.a", .hidden)])
        XCTAssertEqual(hide.pending, [])

        var ask = ArrivalsInbox(pending: ["com.a"])
        XCTAssertEqual(ask.expire(now: t0 + ArrivalsInbox.expiry, firstSeen: { _ in self.t0 }, choice: .ask, table: ["com.a": .visible]), [])
        XCTAssertEqual(ask.pending, [])
    }

    // Given a question whose first-seen time is unknown
    // Then it is kept, not dropped on a guess
    func test_aQuestionWithNoFirstSeenTimeIsKept() {
        var inbox = ArrivalsInbox(pending: ["com.a"])
        _ = inbox.expire(now: t0 + 10 * ArrivalsInbox.expiry, firstSeen: { _ in nil }, choice: .ask, table: [:])

        XCTAssertEqual(inbox.pending, ["com.a"])
    }

    // MARK: storage

    // Given the queue written under `arrivalsPending`
    // Then it reads back in order, and a fresh defaults has none
    func test_pendingRoundTripsThroughUserDefaults() throws {
        let suite = "ArrivalsInboxTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsArrivalsPending(defaults: defaults)

        XCTAssertEqual(store.bundles, [])
        store.bundles = ["com.b", "com.a"]
        XCTAssertEqual(UserDefaultsArrivalsPending(defaults: defaults).bundles, ["com.b", "com.a"])
        XCTAssertEqual(UserDefaultsArrivalsPending.key, "arrivalsPending")
    }

    // The Settings default is stored as 0 ask, 1 show, 2 hide, and unknown values mean Show It.
    func test_newAppDefaultStorage() {
        XCTAssertEqual([NewAppDefault.ask, .show, .hide].map(\.rawValue), [0, 1, 2])
        XCTAssertNil(NewAppDefault.ask.section)
        XCTAssertEqual(NewAppDefault.show.section, .visible)
        XCTAssertEqual(NewAppDefault.hide.section, .hidden)
        XCTAssertNil(NewAppDefault(rawValue: 7))
    }
}
