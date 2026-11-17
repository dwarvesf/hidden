//
//  ArrivalsInbox.swift
//  Hidden Bar
//
//  Copyright © 2026 Console Labs. All rights reserved.
//

import Foundation

// What happens to an app that adds its first icon (macOS 27, direct build).
// Raw values are the stored `newAppDefaultSection`: 1 is the 1.12 behavior.
enum NewAppDefault: Int, Equatable {
    case ask = 0
    case show = 1
    case hide = 2

    // The section a never-seen app goes to without asking; nil when it is asked.
    var section: MenuBarSection? {
        switch self {
        case .ask: return nil
        case .show: return .visible
        case .hide: return .hidden
        }
    }
}

// The answer to "show or hide?" in the arrivals prompt.
enum ArrivalAnswer: Equatable {
    case show
    case hide
    case alwaysHide

    var section: MenuBarSection {
        switch self {
        case .show: return .visible
        case .hide: return .hidden
        case .alwaysHide: return .alwaysHidden
        }
    }
}

// The decision logic of the arrivals inbox, free of AppKit and storage: which
// first-seen apps wait for an answer, where each one goes, and when a question
// lapses. The caller reads the arrivals from MenuBarItemCatalog (an app is an
// arrival only the first time it is ever read, and the first run of the
// catalog records the apps already on the bar without announcing them, so an
// upgrade asks about nothing) and writes the placements it returns.
struct ArrivalsInbox: Equatable {
    // A question that nobody answers lapses after this long and the default applies.
    static let expiry: TimeInterval = 24 * 60 * 60

    struct Placement: Equatable {
        let bundle: String
        let section: MenuBarSection
    }

    // Bundle ids waiting for an answer, oldest first. Persisted.
    private(set) var pending: [String]
    // Arrivals this run has already dealt with. A catalog notification repeats the
    // latest read's arrivals on every later publish; handling each bundle once keeps
    // a repeat from undoing an answer or the user's own edit.
    private var handled: Set<String> = []

    init(pending: [String] = []) {
        self.pending = pending
    }

    // Apps a read found for the first time. Returns the sections to write.
    // `pinsSections` false (the beta is off): the table is not applied, so nobody
    // is placed or asked. Ask Me keeps the app shown until it is answered; Show It places nothing.
    mutating func receive(_ arrivals: [String], choice: NewAppDefault, pinsSections: Bool,
                          table: [String: MenuBarSection]) -> [Placement] {
        var placements: [Placement] = []
        for bundle in arrivals where Self.isAskable(bundle) && handled.insert(bundle).inserted {
            // Show It is 1.12 exactly: the engine's resolver already places a never-seen
            // app (launched apps visible, others at their read position), and a pinned
            // entry this catalog never saw stays as it is.
            guard pinsSections, choice != .show else { continue }
            let section = choice.section ?? .visible
            if choice == .ask, !pending.contains(bundle) {
                pending.append(bundle)
            }
            if table[bundle] != section {
                placements.append(Placement(bundle: bundle, section: section))
            }
        }
        return placements
    }

    // The user's answer for one waiting app. Nil when it is not waiting.
    mutating func answer(_ bundle: String, _ answer: ArrivalAnswer) -> Placement? {
        guard let index = pending.firstIndex(of: bundle) else { return nil }
        pending.remove(at: index)
        return Placement(bundle: bundle, section: answer.section)
    }

    // "Show All" / "Hide All": one answer for everything waiting.
    mutating func answerAll(_ answer: ArrivalAnswer) -> [Placement] {
        let answered = pending.map { Placement(bundle: $0, section: answer.section) }
        pending = []
        return answered
    }

    // Drops the questions that are over their time. The Settings default applies to
    // them; Ask Me leaves the app where it is, shown.
    mutating func expire(now: Date, firstSeen: (String) -> Date?, choice: NewAppDefault,
                         table: [String: MenuBarSection]) -> [Placement] {
        let lapsed = pending.filter { bundle in
            firstSeen(bundle).map { now.timeIntervalSince($0) >= Self.expiry } ?? false
        }
        guard !lapsed.isEmpty else { return [] }
        pending.removeAll { lapsed.contains($0) }
        guard let section = choice.section else { return [] }
        return lapsed.filter { table[$0] != section }.map { Placement(bundle: $0, section: section) }
    }

    // An app the user removed from the Icons list is no question any more.
    mutating func prune(keeping table: [String: MenuBarSection]) {
        pending.removeAll { table[$0] == nil }
    }

    // Debug hook: asks about a bundle as if a read had found it.
    mutating func inject(_ bundle: String) {
        handled.insert(bundle)
        if !pending.contains(bundle) { pending.append(bundle) }
    }

    // macOS's own extras are drawn by Control Center: there is no app to ask about.
    static func isAskable(_ bundle: String) -> Bool {
        return MenuBarCatalogState.isCataloged(bundle)
    }
}

// The pending questions, kept across launches under `arrivalsPending`.
struct UserDefaultsArrivalsPending {
    // Equal to UserDefaults.Key.arrivalsPending; written out so the logic tests need no Preferences code.
    static let key = "arrivalsPending"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = AppDefaults.store) {
        self.defaults = defaults
    }

    var bundles: [String] {
        get { defaults.stringArray(forKey: Self.key) ?? [] }
        nonmutating set { defaults.set(newValue, forKey: Self.key) }
    }
}
