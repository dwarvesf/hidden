//
//  MenuBarCatalogState.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import Foundation

// The AppKit-free part of MenuBarItemCatalog: which apps were seen, when, in
// which section, and which of them are new since the last read.
struct MenuBarCatalogState: Equatable {
    // When each app was first read. Persisted by the catalog.
    private(set) var firstSeen: [String: Date]
    // Whether a catalog was persisted before this one. The first read of the
    // first run records every app it finds without calling any of them new:
    // upgrading must not announce the apps the user already has.
    private(set) var isSeeded: Bool
    private(set) var sections: [String: MenuBarSection] = [:]
    // The owner's name as the Accessibility read gave it, for apps that are not installed.
    private(set) var ownerNames: [String: String] = [:]

    // `firstSeen` nil means nothing was persisted yet.
    init(firstSeen: [String: Date]?) {
        self.firstSeen = firstSeen ?? [:]
        isSeeded = firstSeen != nil
    }

    // macOS's own extras are drawn by Control Center; they are not an app to
    // list, search for or announce.
    static func isCataloged(_ bundle: String) -> Bool {
        return bundle != MenuBarLayoutResolver.systemExtrasBundle
    }

    // Folds in one read taken while nothing was hidden, and returns the bundle
    // ids seen for the first time. `table` is the pinned-sections table: apps in
    // it that this read did not list are recorded too, without being new.
    mutating func apply(read: [String: MenuBarSection], ownerNames names: [String: String] = [:],
                        table: [String: MenuBarSection] = [:], now: Date) -> [String] {
        let listed = read.keys.filter(Self.isCataloged)
        let arrivals = isSeeded ? listed.filter { firstSeen[$0] == nil }.sorted() : []
        for bundle in Set(listed).union(table.keys.filter(Self.isCataloged)) where firstSeen[bundle] == nil {
            firstSeen[bundle] = now
        }
        isSeeded = true
        for (bundle, section) in table where Self.isCataloged(bundle) {
            sections[bundle] = section
        }
        for (bundle, section) in read where Self.isCataloged(bundle) {
            sections[bundle] = section
        }
        for (bundle, name) in names where Self.isCataloged(bundle) {
            ownerNames[bundle] = name
        }
        return arrivals
    }

    // The table changed (Preferences or a debug hook): its sections win for
    // the apps it names.
    mutating func apply(table: [String: MenuBarSection]) {
        for (bundle, section) in table where Self.isCataloged(bundle) && firstSeen[bundle] != nil {
            sections[bundle] = section
        }
    }

    // Every cataloged bundle, in a stable order.
    var bundles: [String] {
        return firstSeen.keys.sorted()
    }
}
