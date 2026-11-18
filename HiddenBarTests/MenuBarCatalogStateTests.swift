//
//  MenuBarCatalogStateTests.swift
//  HiddenBarTests
//
//  Copyright © 2026 Console Labs. All rights reserved.
//

import XCTest

// The catalog's merge and diff logic: fixtures only, no AppKit, no persistence.
final class MenuBarCatalogStateTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)
    private let t1 = Date(timeIntervalSince1970: 2_000)
    private let t2 = Date(timeIntervalSince1970: 3_000)

    // Given nothing persisted, when the first read lists apps
    // Then all are recorded at that time and none is called new
    func test_firstRunSeedsEveryAppWithoutArrivals() {
        var state = MenuBarCatalogState(firstSeen: nil)
        let arrivals = state.apply(read: ["com.a": .visible, "com.b": .hidden], now: t0)

        XCTAssertEqual(arrivals, [])
        XCTAssertEqual(state.firstSeen, ["com.a": t0, "com.b": t0])
        XCTAssertTrue(state.isSeeded)
    }

    // Given a seeded catalog, when a later read lists an unknown app
    // Then that app is an arrival, once, and keeps its first-seen time
    func test_laterReadReportsOnlyAppsSeenForTheFirstTime() {
        var state = MenuBarCatalogState(firstSeen: nil)
        _ = state.apply(read: ["com.a": .visible], now: t0)

        XCTAssertEqual(state.apply(read: ["com.a": .visible, "com.c": .visible, "com.b": .hidden], now: t1), ["com.b", "com.c"])
        XCTAssertEqual(state.apply(read: ["com.a": .visible, "com.c": .visible, "com.b": .hidden], now: t2), [])
        XCTAssertEqual(state.firstSeen["com.a"], t0)
        XCTAssertEqual(state.firstSeen["com.b"], t1)
    }

    // Given a catalog persisted by an earlier launch, when the new launch reads
    // Then an app the earlier launch knew is not new and an unknown one is
    func test_persistedCatalogRecognisesKnownApps() {
        var state = MenuBarCatalogState(firstSeen: ["com.a": t0])
        let arrivals = state.apply(read: ["com.a": .visible, "com.d": .hidden], now: t1)

        XCTAssertEqual(arrivals, ["com.d"])
        XCTAssertEqual(state.firstSeen["com.a"], t0)
    }

    // Given a persisted but empty catalog, then every app of the next read is an arrival
    func test_emptyPersistedCatalogIsNotAFirstRun() {
        var state = MenuBarCatalogState(firstSeen: [:])
        XCTAssertEqual(state.apply(read: ["com.a": .visible], now: t0), ["com.a"])
    }

    // Given an app that left the bar and came back, then it is not new again
    func test_anAppThatLeftAndReturnedIsNotNewAgain() {
        var state = MenuBarCatalogState(firstSeen: nil)
        _ = state.apply(read: ["com.a": .visible, "com.b": .visible], now: t0)
        _ = state.apply(read: ["com.a": .visible], now: t1)
        XCTAssertEqual(state.apply(read: ["com.a": .visible, "com.b": .visible], now: t2), [])
        XCTAssertEqual(state.sections["com.b"], .visible)
    }

    // Given macOS's own extras in the read, then they are neither listed nor announced
    func test_systemExtrasAreLeftOut() {
        var state = MenuBarCatalogState(firstSeen: [:])
        let extras = MenuBarLayoutResolver.systemExtrasBundle
        let arrivals = state.apply(read: [extras: .hidden, "com.a": .visible], table: [extras: .visible], now: t0)

        XCTAssertEqual(arrivals, ["com.a"])
        XCTAssertEqual(state.bundles, ["com.a"])
        XCTAssertNil(state.sections[extras])
    }

    // Given pinned-sections apps the read did not list, then they are recorded and never announced
    func test_tableAppsAreRecordedWithoutBeingNew() {
        var state = MenuBarCatalogState(firstSeen: [:])
        let arrivals = state.apply(read: ["com.a": .visible], table: ["com.a": .hidden, "com.t": .alwaysHidden], now: t0)

        XCTAssertEqual(arrivals, ["com.a"])
        XCTAssertEqual(state.bundles, ["com.a", "com.t"])
        XCTAssertEqual(state.sections["com.t"], .alwaysHidden)
        XCTAssertEqual(state.firstSeen["com.t"], t0)
    }

    // Given a read and the table disagreeing on one app, then the read's section stands for it
    // (with pinned sections on, the read is already resolved against the table)
    func test_theReadSectionWinsForAListedApp() {
        var state = MenuBarCatalogState(firstSeen: nil)
        _ = state.apply(read: ["com.a": .visible], table: ["com.a": .alwaysHidden], now: t0)
        XCTAssertEqual(state.sections["com.a"], .visible)
    }

    // Given the table edited from Preferences, then known apps follow it and unknown ones stay out
    func test_tableEditsMoveKnownAppsOnly() {
        var state = MenuBarCatalogState(firstSeen: nil)
        _ = state.apply(read: ["com.a": .visible], now: t0)
        state.apply(table: ["com.a": .alwaysHidden, "com.z": .hidden])

        XCTAssertEqual(state.sections["com.a"], .alwaysHidden)
        XCTAssertNil(state.sections["com.z"])
        XCTAssertEqual(state.bundles, ["com.a"])
    }

    // Given an owner name from the Accessibility read, then it is kept for apps that are not installed
    func test_ownerNamesAreKept() {
        var state = MenuBarCatalogState(firstSeen: nil)
        _ = state.apply(read: ["com.a": .visible], ownerNames: ["com.a": "Alpha"], now: t0)
        XCTAssertEqual(state.ownerNames["com.a"], "Alpha")
    }
}
