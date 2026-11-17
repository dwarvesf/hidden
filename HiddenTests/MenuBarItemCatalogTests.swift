//
//  MenuBarItemCatalogTests.swift
//  HiddenTests
//
//  Copyright © 2026 Console Labs. All rights reserved.
//

import XCTest
import AppKit
@testable import Hidden_Bar

#if HIDDENBAR_NATIVE_VISIBILITY

/// Contract: the catalog lists the menu-bar apps the engine's unrestricted reads
/// found, with name, icon, section, first-seen time and running state; it
/// persists first-seen times so only apps new since then are arrivals, and it
/// publishes `.menuBarCatalogChanged` when something a feature would show changes.
/// Mock boundary: a throwaway UserDefaults suite, a private NotificationCenter,
/// a resolver with fixture apps instead of NSWorkspace, and fixture layouts
/// instead of an Accessibility read. No permission, no real app.
final class MenuBarItemCatalogTests: XCTestCase {

    private final class FakeResolver: MenuBarAppResolving {
        var names: [String: String] = [:]
        var running: Set<String> = []
        let icon = NSImage(size: NSSize(width: 16, height: 16))

        func name(of bundle: String) -> String? { names[bundle] }
        func icon(of bundle: String) -> NSImage? { names[bundle] == nil ? nil : icon }
        func isRunning(_ bundle: String) -> Bool { running.contains(bundle) }
    }

    private var suite: String!
    private var defaults: UserDefaults!
    private var center: NotificationCenter!
    private var resolver: FakeResolver!
    private var table: [String: MenuBarSection] = [:]
    private var clock = Date(timeIntervalSince1970: 1_000)
    private var posts: [[String]] = []
    private var postObserver: NSObjectProtocol?

    override func setUp() {
        super.setUp()
        suite = "MenuBarItemCatalogTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        center = NotificationCenter()
        resolver = FakeResolver()
        resolver.names = ["com.alpha": "Alpha", "com.beta": "beta", "com.gamma": "Gamma"]
        resolver.running = ["com.alpha", "com.beta"]
        table = [:]
        posts = []
        postObserver = center.addObserver(forName: .menuBarCatalogChanged, object: nil, queue: nil) { [unowned self] note in
            self.posts.append(note.userInfo?[MenuBarItemCatalog.arrivalsKey] as? [String] ?? ["<missing>"])
        }
    }

    override func tearDown() {
        postObserver.map(center.removeObserver)
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func makeCatalog() -> MenuBarItemCatalog {
        MenuBarItemCatalog(defaults: defaults, center: center, resolver: resolver,
                           pinnedTable: { [unowned self] in self.table }, now: { [unowned self] in self.clock })
    }

    private func read(_ catalog: MenuBarItemCatalog, _ sections: [String: MenuBarSection],
                      owners: [String: String] = [:]) {
        let inventory = owners.map { MenuBarInventoryItem(bundleIdentifier: $0.key, frame: .zero, ownerName: $0.value) }
        catalog.record(layout: MenuBarLayout(sections: sections), inventory: inventory)
    }

    // Given a first read, then each app is listed by name with its section, first-seen time and running state
    func test_firstReadListsEveryAppAndAnnouncesNone() {
        let catalog = makeCatalog()
        read(catalog, ["com.beta": .hidden, "com.alpha": .visible])

        XCTAssertEqual(catalog.entries.map(\.bundleIdentifier), ["com.alpha", "com.beta"], "sorted by name, case blind")
        let alpha = catalog.entry(for: "com.alpha")
        XCTAssertEqual(alpha?.name, "Alpha")
        XCTAssertEqual(alpha?.section, .visible)
        XCTAssertEqual(alpha?.firstSeen, clock)
        XCTAssertEqual(alpha?.isRunning, true)
        XCTAssertEqual(catalog.entry(for: "com.beta")?.section, .hidden)
        XCTAssertEqual(catalog.arrivals, [])
    }

    // Given an app with no installed bundle, then its icon is a placeholder, never nil
    func test_everyEntryHasAnIcon() {
        let catalog = makeCatalog()
        read(catalog, ["com.alpha": .visible, "com.gone": .hidden])
        XCTAssertTrue(catalog.entry(for: "com.alpha")?.icon === resolver.icon)
        XCTAssertNotNil(catalog.entry(for: "com.gone")?.icon)
    }

    // Given an app macOS no longer knows, then its name falls back to the Accessibility owner, then the bundle id
    func test_nameFallsBackToTheOwnerThenTheBundleId() {
        let catalog = makeCatalog()
        read(catalog, ["com.gone": .hidden, "com.nameless": .visible], owners: ["com.gone": "Gone Tool"])
        XCTAssertEqual(catalog.entry(for: "com.gone")?.name, "Gone Tool")
        XCTAssertEqual(catalog.entry(for: "com.nameless")?.name, "com.nameless")
    }

    // Given a later read with a new app, then it is an arrival, published once with the ids
    func test_newAppIsAnArrivalAndIsPublished() {
        let catalog = makeCatalog()
        read(catalog, ["com.alpha": .visible])
        posts = []
        clock = Date(timeIntervalSince1970: 2_000)
        read(catalog, ["com.alpha": .visible, "com.gamma": .hidden])

        XCTAssertEqual(catalog.arrivals, ["com.gamma"])
        XCTAssertEqual(catalog.entry(for: "com.gamma")?.firstSeen, clock)
        XCTAssertEqual(posts, [["com.gamma"]])

        read(catalog, ["com.alpha": .visible, "com.gamma": .hidden])
        XCTAssertEqual(catalog.arrivals, [], "the next read finds nothing new")
        XCTAssertEqual(posts, [["com.gamma"]], "and publishes nothing")
    }

    // Given a read that changes nothing, then nothing is published
    func test_unchangedReadPublishesNothing() {
        let catalog = makeCatalog()
        read(catalog, ["com.alpha": .visible])
        posts = []
        read(catalog, ["com.alpha": .visible])
        XCTAssertTrue(posts.isEmpty)
    }

    // Given an app that moved section, then the entry follows and it is published
    func test_sectionChangeIsPublished() {
        let catalog = makeCatalog()
        read(catalog, ["com.alpha": .visible])
        posts = []
        read(catalog, ["com.alpha": .alwaysHidden])
        XCTAssertEqual(catalog.entry(for: "com.alpha")?.section, .alwaysHidden)
        XCTAssertEqual(posts, [[]])
    }

    // Given a restart, then first-seen times survive and only unknown apps are arrivals
    func test_firstSeenIsPersistedAcrossLaunches() {
        let first = makeCatalog()
        read(first, ["com.alpha": .visible])

        clock = Date(timeIntervalSince1970: 5_000)
        let second = makeCatalog()
        XCTAssertEqual(second.entry(for: "com.alpha")?.firstSeen, Date(timeIntervalSince1970: 1_000), "loaded, not re-read")
        read(second, ["com.alpha": .visible, "com.beta": .hidden])
        XCTAssertEqual(second.arrivals, ["com.beta"])
        XCTAssertEqual(second.entry(for: "com.alpha")?.firstSeen, Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(second.entry(for: "com.beta")?.firstSeen, clock)
    }

    // Given the first launch with 1.13 on a Mac that already has apps, then none is announced
    func test_upgradeDoesNotAnnounceExistingApps() {
        table = ["com.alpha": .visible, "com.beta": .hidden]
        let catalog = makeCatalog()
        XCTAssertEqual(catalog.entries.count, 0, "nothing is cataloged before the first read")
        read(catalog, ["com.alpha": .visible, "com.beta": .hidden, "com.gamma": .visible])
        XCTAssertEqual(catalog.arrivals, [])
        XCTAssertEqual(catalog.entries.count, 3)
    }

    // Given pinned sections, then an app the read did not list keeps its pinned section
    // and a Preferences edit moves it at once
    func test_pinnedTableFeedsSectionsAndEdits() {
        let catalog = makeCatalog()
        table = ["com.beta": .alwaysHidden]
        read(catalog, ["com.alpha": .visible, "com.beta": .alwaysHidden])
        XCTAssertEqual(catalog.entry(for: "com.beta")?.section, .alwaysHidden)

        posts = []
        table = ["com.beta": .visible]
        center.post(name: .pinnedSectionsChanged, object: nil)
        XCTAssertEqual(catalog.entry(for: "com.beta")?.section, .visible)
        XCTAssertEqual(posts, [[]])
    }

    // Given an app that starts or quits, then isRunning follows and it is published
    func test_launchesAndQuitsUpdateIsRunning() {
        let catalog = makeCatalog()
        let workspace = NotificationCenter()
        catalog.observeLaunches(on: [workspace])
        read(catalog, ["com.alpha": .visible, "com.gamma": .hidden])
        posts = []

        resolver.running.insert("com.gamma")
        workspace.post(name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        XCTAssertEqual(catalog.entry(for: "com.gamma")?.isRunning, true)
        XCTAssertEqual(posts, [[]])

        resolver.running.remove("com.alpha")
        workspace.post(name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        XCTAssertEqual(catalog.entry(for: "com.alpha")?.isRunning, false)
        XCTAssertEqual(posts.count, 2)

        workspace.post(name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        XCTAssertEqual(posts.count, 2, "no change, no post")
    }

    // Given macOS's own extras in a read, then they are not listed
    func test_systemExtrasAreNotListed() {
        let catalog = makeCatalog()
        read(catalog, [MenuBarLayoutResolver.systemExtrasBundle: .hidden, "com.alpha": .visible])
        XCTAssertEqual(catalog.entries.map(\.bundleIdentifier), ["com.alpha"])
    }

    // Given the dump-inventory debug hook, then the catalog is JSON with one object per app
    func test_dumpInventoryJSON() throws {
        let catalog = makeCatalog()
        read(catalog, ["com.alpha": .visible])
        clock = Date(timeIntervalSince1970: 2_000)
        read(catalog, ["com.alpha": .visible, "com.beta": .hidden])

        let object = try JSONSerialization.jsonObject(with: try catalog.debugJSON()) as? [String: Any]
        let json = try XCTUnwrap(object)
        XCTAssertEqual(json["arrivals"] as? [String], ["com.beta"])
        let rows = try XCTUnwrap(json["entries"] as? [[String: Any]])
        XCTAssertEqual(rows.map { $0["bundleIdentifier"] as? String }, ["com.alpha", "com.beta"])
        XCTAssertEqual(rows[1]["name"] as? String, "beta")
        XCTAssertEqual(rows[1]["section"] as? String, "hidden")
        XCTAssertEqual(rows[1]["isRunning"] as? Bool, true)
        XCTAssertEqual(rows[1]["firstSeen"] as? String, ISO8601DateFormatter().string(from: clock))
    }
}

#endif
