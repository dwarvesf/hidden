//
//  PaletteModel.swift
//  Hidden Bar
//
//  Copyright © 2026 Console Labs. All rights reserved.
//

import Foundation

/// What the palette depends on besides the apps: both are read when it opens.
struct PaletteEnvironment: Equatable {
    var accessibilityTrusted: Bool
    /// False when the engine cannot hide anything right now (outside Applications,
    /// no native API). Then nothing is hidden and there is nothing to find.
    var engineAvailable: Bool
    /// False when the pinned-sections beta is off: a section move would write a
    /// table nothing reads, so the palette offers only opening.
    var pinsSections = true
    /// Apps presentation mode keeps out of sight while it is on. They are left
    /// out of the list, and out of every hint that names an app, so the room
    /// never learns they are there.
    var hiddenWhilePresenting: Set<String> = []
}

/// A line in the result list.
enum PaletteListItem: Equatable {
    case header(MenuBarSection)
    case row(PaletteMatch)
}

/// What the panel shows under the search field.
enum PaletteContent: Equatable {
    case results([PaletteListItem])
    /// `shownApp`: a running app that matches but is not hidden. `quitApp`: a hidden
    /// app that matches but has quit since the last read.
    case noMatch(query: String, shownApp: String?, quitApp: String?)
    case nothingHidden
    case accessibilityOff
    /// macOS keeps Focus, Siri and Now Playing out of reach while icons are hidden.
    case systemItem(name: String)
    case engineUnavailable
    /// Return found the app but its icon would not press.
    case cannotOpen(appName: String)
}

/// The palette's state: the query, the list it gives, and the selection.
/// Pure, so the rules (which edge state wins, how the selection moves) are tested
/// without a window.
struct PaletteModel: Equatable {
    /// macOS items that leave Accessibility while hidden, so they cannot be listed.
    static let systemItemNames = ["Focus", "Siri", "Now Playing"]

    private(set) var candidates: [PaletteCandidate]
    var environment: PaletteEnvironment
    private(set) var query = ""
    private(set) var content: PaletteContent
    private(set) var selectedIndex = 0
    private var failure: String?

    init(candidates: [PaletteCandidate], environment: PaletteEnvironment) {
        self.candidates = candidates
        self.environment = environment
        content = .nothingHidden
        recompute()
    }

    mutating func setQuery(_ newValue: String) {
        guard newValue != query else { return }
        query = newValue
        failure = nil
        selectedIndex = 0
        recompute()
    }

    /// The catalog changed while the palette is open.
    mutating func update(candidates newValue: [PaletteCandidate], environment newEnvironment: PaletteEnvironment) {
        let keep = selected?.bundleIdentifier
        candidates = newValue
        environment = newEnvironment
        recompute()
        if let keep, let index = rows.firstIndex(where: { $0.candidate.bundleIdentifier == keep }) {
            selectedIndex = index
        }
    }

    /// Return found the app but could not press its icon.
    mutating func showCannotOpen(appName: String) {
        failure = appName
        recompute()
    }

    /// The matches in list order, without the headers.
    var rows: [PaletteMatch] {
        guard case .results(let items) = content else { return [] }
        return items.compactMap { item in
            if case .row(let match) = item { return match }
            return nil
        }
    }

    var selected: PaletteCandidate? {
        return rows.indices.contains(selectedIndex) ? rows[selectedIndex].candidate : nil
    }

    /// Moves the selection one row, stopping at the ends.
    mutating func moveSelection(by step: Int) {
        guard !rows.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + step, 0), rows.count - 1)
    }

    mutating func select(bundle: String) {
        if let index = rows.firstIndex(where: { $0.candidate.bundleIdentifier == bundle }) {
            selectedIndex = index
        }
    }

    private mutating func recompute() {
        selectedIndex = 0
        content = Self.resolve(query: query, candidates: candidates, environment: environment, failure: failure)
    }

    static func resolve(query: String, candidates allCandidates: [PaletteCandidate], environment: PaletteEnvironment,
                        failure: String? = nil) -> PaletteContent {
        // The permission comes first: without it nothing below can be read or pressed.
        guard environment.accessibilityTrusted else { return .accessibilityOff }
        guard environment.engineAvailable else { return .engineUnavailable }
        if let failure { return .cannotOpen(appName: failure) }

        let candidates = allCandidates.filter { !environment.hiddenWhilePresenting.contains($0.bundleIdentifier) }
        let findable = candidates.filter(\.isFindable)
        guard !findable.isEmpty else { return .nothingHidden }

        let matches = PaletteRanking.rank(query: query, in: findable)
        if !matches.isEmpty { return .results(listItems(matches, grouped: query.trimmingCharacters(in: .whitespaces).isEmpty)) }

        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let system = systemItemName(matching: typed) { return .systemItem(name: system) }
        let others = candidates.filter { !$0.isFindable }
        let shown = PaletteRanking.rank(query: typed, in: others.filter { $0.section == .visible && $0.isRunning }).first
        let quit = PaletteRanking.rank(query: typed, in: others.filter { $0.section != .visible && !$0.isRunning }).first
        return .noMatch(query: typed, shownApp: shown?.candidate.name, quitApp: quit?.candidate.name)
    }

    /// Section headers go in when every section's rows sit together, which is
    /// always so for an empty query and often so for a short one. Ranked results
    /// that interleave sections show a section label on each row instead.
    static func listItems(_ matches: [PaletteMatch], grouped: Bool) -> [PaletteListItem] {
        let sections = matches.map(\.candidate.section)
        let runs = zip(sections, sections.dropFirst()).filter { $0 != $1 }.count + 1
        guard grouped || runs == Set(sections).count else { return matches.map { .row($0) } }
        var items: [PaletteListItem] = []
        var current: MenuBarSection?
        for match in matches {
            if match.candidate.section != current {
                current = match.candidate.section
                items.append(.header(match.candidate.section))
            }
            items.append(.row(match))
        }
        return items
    }

    /// "focus", "Sir" and "now p" name a macOS item; one letter would name too many.
    static func systemItemName(matching query: String) -> String? {
        let typed = PaletteRanking.fold(query)
        guard typed.count >= 2 else { return nil }
        return systemItemNames.first { PaletteRanking.fold($0).starts(with: typed) }
    }
}
