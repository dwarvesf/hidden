//
//  ArrivalsControllerTests.swift
//  HiddenTests
//
//  Copyright © 2026 Console Labs. All rights reserved.
//

import XCTest
import AppKit
@testable import Hidden_Bar

#if HIDDENBAR_NATIVE_VISIBILITY

/// Contract: the controller turns the catalog's arrivals into placements and waiting
/// questions as the Settings default says, persists the questions under
/// `arrivalsPending`, applies an answer to the pinned-sections table, tells the arrow
/// and the Icons list when the queue changes, and never asks about an app twice.
/// Mock boundary: a throwaway UserDefaults suite, a private NotificationCenter, an
/// in-memory section table, a catalog with fixture apps and fixture reads. No
/// Accessibility, no window, no real app.
final class ArrivalsControllerTests: XCTestCase {
    private final class FakeResolver: MenuBarAppResolving {
        func name(of bundle: String) -> String? { bundle.replacingOccurrences(of: "com.test.", with: "").capitalized }
        func icon(of bundle: String) -> NSImage? { NSImage(size: NSSize(width: 16, height: 16)) }
        func isRunning(_ bundle: String) -> Bool { true }
    }

    private var suite = ""
    private var defaults: UserDefaults!
    private var center: NotificationCenter!
    private var table: InMemorySectionMemory!
    private var catalog: MenuBarItemCatalog!
    private var choice: NewAppDefault = .ask
    private var pinsSections = true
    private var clock = Date(timeIntervalSince1970: 1_000_000)
    private var changes = 0
    private var observers: [NSObjectProtocol] = []

    override func setUp() {
        super.setUp()
        suite = "ArrivalsControllerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        center = NotificationCenter()
        table = InMemorySectionMemory()
        choice = .ask
        pinsSections = true
        changes = 0
        catalog = makeCatalog()
        observers = [center.addObserver(forName: .arrivalsChanged, object: nil, queue: nil) { [unowned self] _ in changes += 1 }]
    }

    override func tearDown() {
        observers.forEach(center.removeObserver)
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func makeCatalog() -> MenuBarItemCatalog {
        MenuBarItemCatalog(defaults: defaults, center: center, resolver: FakeResolver(),
                           pinnedTable: { [unowned self] in table.sections }, now: { [unowned self] in clock })
    }

    private func makeController(place: ((MenuBarSection, String) -> Void)? = nil) -> ArrivalsController {
        let controller = ArrivalsController(defaults: defaults, center: center, table: table,
                                            choice: { [unowned self] in choice }, pinsSections: { [unowned self] in pinsSections },
                                            lookup: { [unowned self] in catalog.entry(for: $0) },
                                            place: place ?? { [unowned self] section, bundle in table.sections[bundle] = section },
                                            now: { [unowned self] in clock })
        controller.start()
        return controller
    }

    /// One unrestricted read of the bar. The first read of a catalog seeds it.
    private func read(_ bundles: [String], section: MenuBarSection = .hidden) {
        let layout = MenuBarLayout(sections: Dictionary(uniqueKeysWithValues: bundles.map { ($0, section) }))
        // The engine writes the table from the read before the catalog hears of it.
        for bundle in bundles where table.sections[bundle] == nil { table.sections[bundle] = section }
        catalog.record(layout: layout, inventory: [])
    }

    private func seededController() -> ArrivalsController {
        let controller = makeController()
        read(["com.test.old"])
        return controller
    }

    // Given Show It, when an app arrives that the table has at its hidden read position
    // Then the controller writes nothing, nothing waits, and nothing is announced
    func test_showIt_writesNothingAndAsksNothing() {
        choice = .show
        var placed: [String] = []
        let controller = makeController(place: { _, bundle in placed.append(bundle) })
        read(["com.test.old"])
        read(["com.test.old", "com.test.new"])

        XCTAssertEqual(table.sections["com.test.new"], .hidden)
        XCTAssertEqual(placed, [])
        XCTAssertEqual(controller.pending, [])
        XCTAssertEqual(changes, 0)
    }

    // Given Hide It, when an app arrives
    // Then it is placed hidden on first sight and never asked
    func test_hideIt_placesHiddenAndAsksNothing() {
        choice = .hide
        let controller = seededController()
        table.sections["com.test.new"] = .visible
        read(["com.test.old", "com.test.new"], section: .visible)

        XCTAssertEqual(table.sections["com.test.new"], .hidden)
        XCTAssertEqual(controller.pending, [])
    }

    // Given the upgrade run (the catalog seeds on its first read)
    // Then apps already on the bar are never asked, whatever the default is
    func test_firstReadSeedsWithoutAsking() {
        choice = .ask
        let controller = makeController()
        read(["com.test.a", "com.test.b"])

        XCTAssertEqual(controller.pending, [])
        XCTAssertEqual(changes, 0)
    }

    // Given Ask Me, when an app arrives
    // Then it waits under arrivalsPending, stays visible in the table, and the arrow and list are told
    func test_askMe_keepsTheAppShownAndQueuesIt() {
        let controller = seededController()
        read(["com.test.old", "com.test.new"])

        XCTAssertEqual(controller.pending, ["com.test.new"])
        XCTAssertEqual(table.sections["com.test.new"], .visible)
        XCTAssertEqual(defaults.stringArray(forKey: "arrivalsPending"), ["com.test.new"])
        XCTAssertEqual(changes, 1)
    }

    // Given a waiting question and presentation mode on
    // When the presenter is asked to open from the arrow
    // Then no popover opens (the room sees the screen); the question is still waiting, and opens once the mode ends
    func test_arrivalsPrompt_waitsWhilePresenting() {
        let controller = seededController()
        read(["com.test.old", "com.test.new"])
        var presenting = true
        var shown = 0
        let presenter = ArrivalsPresenter(controller: controller, isSuppressed: { presenting },
                                          showPopover: { _, _ in shown += 1 }, openSettings: {})
        let button = NSStatusBarButton(frame: NSRect(x: 0, y: 0, width: 20, height: 20))

        presenter.present(from: button)
        XCTAssertEqual(shown, 0)
        XCTAssertEqual(controller.pending, ["com.test.new"], "the question waits")

        presenting = false
        presenter.present(from: button)
        XCTAssertEqual(shown, 1)
        presenter.close()
    }

    // Given a waiting app, when the answer is Hide
    // Then the table says hidden, the entry is cleared in memory and on disk, and the arrow is told
    func test_answer_writesTheSectionAndClearsTheEntry() {
        let controller = seededController()
        read(["com.test.old", "com.test.new"])

        XCTAssertTrue(controller.answer("com.test.new", .hide))
        XCTAssertEqual(table.sections["com.test.new"], .hidden)
        XCTAssertEqual(controller.pending, [])
        XCTAssertEqual(defaults.stringArray(forKey: "arrivalsPending"), [])
        XCTAssertEqual(changes, 2)
        XCTAssertFalse(controller.answer("com.test.new", .show), "a stale prompt answers nothing")
        XCTAssertEqual(table.sections["com.test.new"], .hidden)
    }

    // Given the catalog republishing the latest arrivals after the answer (it does, on any later change)
    // Then the answer stands and the app is not asked again
    func test_aRepublishedArrivalNeverReAsks() {
        let controller = seededController()
        read(["com.test.old", "com.test.new"])
        controller.answer("com.test.new", .hide)

        controller.catalogChanged(arrivals: ["com.test.new"])
        XCTAssertEqual(controller.pending, [])
        XCTAssertEqual(table.sections["com.test.new"], .hidden)
    }

    // Given an answered app and a restart (new controller and catalog on the same defaults)
    // Then a read of the same bar asks nothing
    func test_anAppIsAskedAtMostOnce_acrossARestart() {
        let first = seededController()
        read(["com.test.old", "com.test.new"])
        first.answer("com.test.new", .show)

        catalog = makeCatalog()
        let second = makeController()
        read(["com.test.old", "com.test.new"])
        XCTAssertEqual(second.pending, [])
    }

    // Given a question waiting at quit
    // When Hidden Bar starts again
    // Then it is still waiting, and the same read does not queue it twice
    func test_aWaitingQuestionSurvivesARestart() {
        let first = seededController()
        read(["com.test.old", "com.test.new"])
        XCTAssertEqual(first.pending, ["com.test.new"])

        catalog = makeCatalog()
        let second = makeController()
        XCTAssertEqual(second.pending, ["com.test.new"])
        read(["com.test.old", "com.test.new"])
        XCTAssertEqual(second.pending, ["com.test.new"])
    }

    // Given several apps found by one read, then Hide All
    // Then each is placed hidden and nothing waits
    func test_severalArrivals_hideAll() {
        let controller = seededController()
        read(["com.test.old", "com.test.a", "com.test.b", "com.test.c"])
        XCTAssertEqual(Set(controller.pending), ["com.test.a", "com.test.b", "com.test.c"])

        controller.answerAll(.hide)
        XCTAssertEqual(controller.pending, [])
        for bundle in ["com.test.a", "com.test.b", "com.test.c"] {
            XCTAssertEqual(table.sections[bundle], .hidden)
        }
    }

    // Given the beta off
    // Then an arrival is neither placed by the controller nor asked
    func test_pinnedSectionsOff_doesNothing() {
        pinsSections = false
        var placed: [String] = []
        let controller = makeController(place: { _, bundle in placed.append(bundle) })
        read(["com.test.old"])
        read(["com.test.old", "com.test.new"])

        XCTAssertEqual(controller.pending, [])
        XCTAssertEqual(placed, [])
    }

    // Given a question a day old
    // When the controller refreshes
    // Then it lapses; with the default now Hide It the app goes hidden
    func test_aQuestionLapsesAfterADay() {
        let controller = seededController()
        read(["com.test.old", "com.test.new"])
        choice = .hide

        clock += ArrivalsInbox.expiry - 1
        controller.refresh()
        XCTAssertEqual(controller.pending, ["com.test.new"])

        clock += 1
        controller.refresh()
        XCTAssertEqual(controller.pending, [])
        XCTAssertEqual(table.sections["com.test.new"], .hidden)
        XCTAssertEqual(defaults.stringArray(forKey: "arrivalsPending"), [])
    }

    // Given a waiting app the user removes from the Icons list
    // Then the question goes with it
    func test_removingAnAppFromTheListDropsItsQuestion() {
        let controller = seededController()
        read(["com.test.old", "com.test.new"])

        table.sections.removeValue(forKey: "com.test.new")
        controller.refresh()
        XCTAssertEqual(controller.pending, [])
    }

    // Given the default place closure
    // Then an answer is written through PinnedSectionEdits.set: the table changes and the engine is told
    func test_answerGoesThroughPinnedSectionEdits() {
        let controller = ArrivalsController(defaults: defaults, center: center, table: table, choice: { .ask },
                                            pinsSections: { true }, lookup: { _ in nil })
        controller.debugInject("com.test.x")
        var told = 0
        let observer = NotificationCenter.default.addObserver(forName: .pinnedSectionsChanged, object: nil, queue: nil) { _ in told += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }

        controller.answer("com.test.x", .alwaysHide)
        XCTAssertEqual(table.sections["com.test.x"], .alwaysHidden)
        XCTAssertEqual(told, 1)
    }

    // Given an inventory where one app has two items
    // Then its prompt row says two icons
    func test_iconCountComesFromTheInventory() {
        let controller = seededController()
        let frame = CGRect(x: 0, y: 0, width: 20, height: 20)
        controller.noteInventory([MenuBarInventoryItem(bundleIdentifier: "com.test.docker", frame: frame),
                                  MenuBarInventoryItem(bundleIdentifier: "com.test.docker", frame: frame),
                                  MenuBarInventoryItem(bundleIdentifier: "com.test.new", frame: frame)])

        XCTAssertEqual(controller.info(for: "com.test.docker").iconCount, 2)
        XCTAssertEqual(controller.info(for: "com.test.new").iconCount, 1)
        XCTAssertEqual(controller.info(for: "com.test.unknown").iconCount, 1)
    }
}

/// The prompt as the board draws it: what it says and what its buttons do.
final class ArrivalsPromptTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func info(_ bundle: String, ago: TimeInterval = 5, running: Bool = true, icons: Int = 1) -> ArrivalInfo {
        ArrivalInfo(bundle: bundle, name: bundle.capitalized, icon: NSImage(), firstSeen: now.addingTimeInterval(-ago),
                    isRunning: running, iconCount: icons)
    }

    private func views(in root: NSView) -> [NSView] {
        root.subviews + root.subviews.flatMap { views(in: $0) }
    }

    // Given one to three waiting apps
    // Then the title is the board's, every app has a row, and the footer is the hint
    func test_fewArrivals_listEachAndHint() {
        let model = ArrivalsPromptModel.make(infos: [info("raycast"), info("tailscale", ago: 7200)], now: now)

        XCTAssertEqual(model.title, "New in your menu bar")
        XCTAssertEqual(model.rows.map(\.name), ["Raycast", "Tailscale"])
        XCTAssertEqual(model.rows.map(\.caption), ["Added an icon just now", "Added an icon 2 hours ago"])
        XCTAssertEqual(model.footer, .hint)
    }

    // Given six waiting apps
    // Then three show, the title counts them, and the footer says "and 3 more" with bulk answers
    func test_manyArrivals_showThreeAndABulkFooter() {
        let model = ArrivalsPromptModel.make(infos: (1...6).map { info("app\($0)") }, now: now)

        XCTAssertEqual(model.title, "6 new apps in your menu bar")
        XCTAssertEqual(model.rows.count, 3)
        XCTAssertEqual(model.footer, .bulk(more: 3))
    }

    // Given an app with two icons, and one that is not running
    // Then the first says they move together, the second that it stays shown until chosen
    func test_edgeCaptions() {
        XCTAssertEqual(ArrivalsPromptModel.caption(for: info("docker", icons: 2), now: now), "Added 2 icons. They show or hide together.")
        XCTAssertEqual(ArrivalsPromptModel.caption(for: info("gone", running: false, icons: 2), now: now),
                       "Not running now. It stays shown until you choose.")
    }

    // Given the prompt for two apps
    // When pressing Hide in one row, Always hide in another, and Hide All
    // Then each press reports the app and the answer
    func test_buttonsReportAnswers() throws {
        let view = ArrivalsPromptView(model: ArrivalsPromptModel.make(infos: [info("a"), info("b")], now: now))
        var answers: [String] = []
        view.onAnswer = { bundle, answer in answers.append("\(bundle):\(answer)") }
        let all = views(in: view)

        let segments = try XCTUnwrap(all.compactMap { $0 as? NSSegmentedControl }.first { $0.identifier?.rawValue == ArrivalsPromptView.showIdentifier("a") })
        segments.selectedSegment = 1
        segments.sendAction(segments.action, to: segments.target)
        segments.selectedSegment = 0
        segments.sendAction(segments.action, to: segments.target)

        let more = try XCTUnwrap(all.compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == ArrivalsPromptView.alwaysHideIdentifier("b") })
        let item = try XCTUnwrap(more.menu?.items.first)
        XCTAssertEqual(item.title, "Always hide")
        _ = item.target?.perform(item.action, with: item)

        XCTAssertEqual(answers, ["a:hide", "a:show", "b:alwaysHide"])
    }

    // Given six apps, when pressing Hide All and Show All
    // Then the bulk callback gets each answer
    func test_bulkButtons() throws {
        let view = ArrivalsPromptView(model: ArrivalsPromptModel.make(infos: (1...5).map { info("app\($0)") }, now: now))
        var bulk: [ArrivalAnswer] = []
        view.onAnswerAll = { bulk.append($0) }
        let buttons = views(in: view).compactMap { $0 as? NSButton }
        try XCTUnwrap(buttons.first { $0.identifier?.rawValue == ArrivalsPromptView.hideAllIdentifier }).performClick(nil)
        try XCTUnwrap(buttons.first { $0.identifier?.rawValue == ArrivalsPromptView.showAllIdentifier }).performClick(nil)

        XCTAssertEqual(bulk, [.hide, .show])
    }

    // The prompt is drawn at the board's width and grows with its rows.
    func test_promptSizeFollowsItsRows() {
        let few = ArrivalsPromptView(model: ArrivalsPromptModel.make(infos: [info("a")], now: now)).fittingContentSize
        let more = ArrivalsPromptView(model: ArrivalsPromptModel.make(infos: [info("a"), info("b"), info("c")], now: now)).fittingContentSize

        XCTAssertEqual(few.width, ArrivalsPromptView.width)
        XCTAssertGreaterThan(more.height, few.height + 80)
    }
}

#endif
