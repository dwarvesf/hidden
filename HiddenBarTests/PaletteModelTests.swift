//
//  PaletteModelTests.swift
//  HiddenBarTests
//
//  Copyright © 2026 Console Labs. All rights reserved.
//

import XCTest

/// Contract: which of the board's states the palette shows for a query, an
/// inventory and a permission, and how the selection moves.
/// Serves: PaletteModel.
/// Mock boundary: none. Plain fixtures; no catalog, no Accessibility.
final class PaletteModelTests: XCTestCase {

    private let ready = PaletteEnvironment(accessibilityTrusted: true, engineAvailable: true)

    private func app(_ name: String, _ section: MenuBarSection = .hidden, running: Bool = true) -> PaletteCandidate {
        return PaletteCandidate(bundleIdentifier: "com.test.\(name.lowercased().replacingOccurrences(of: " ", with: ""))",
                                name: name, section: section, isRunning: running)
    }

    private func model(_ candidates: [PaletteCandidate], query: String = "", environment: PaletteEnvironment? = nil) -> PaletteModel {
        var model = PaletteModel(candidates: candidates, environment: environment ?? ready)
        model.setQuery(query)
        return model
    }

    // MARK: edge states

    // Given a macOS 27 Mac without the Accessibility grant
    // When opening, even with apps and a query
    // Then the permission state shows
    func test_accessibilityOff_winsOverEverything() {
        let environment = PaletteEnvironment(accessibilityTrusted: false, engineAvailable: false)
        XCTAssertEqual(model([app("Paste")], query: "pa", environment: environment).content, .accessibilityOff)
        XCTAssertEqual(model([], environment: environment).content, .accessibilityOff)
    }

    // Given the engine cannot hide anything right now
    // When opening
    // Then the palette says so
    func test_engineUnavailable() {
        let environment = PaletteEnvironment(accessibilityTrusted: true, engineAvailable: false)
        XCTAssertEqual(model([app("Paste")], environment: environment).content, .engineUnavailable)
    }

    // Given an empty catalog, or every app visible, or the hidden ones quit since the read
    // When opening
    // Then "nothing hidden"
    func test_nothingHidden_whenNoRunningAppIsHidden() {
        XCTAssertEqual(model([]).content, .nothingHidden)
        XCTAssertEqual(model([app("Bear", .visible)]).content, .nothingHidden)
        XCTAssertEqual(model([app("Paste", .hidden, running: false)]).content, .nothingHidden, "stale: the app quit")
    }

    // Given a query matching only a shown app
    // When typing
    // Then no match, naming the app that is shown
    func test_noMatch_namesTheShownApp() {
        let state = model([app("Paste"), app("zoom.us", .visible)], query: "zoom")
        XCTAssertEqual(state.content, .noMatch(query: "zoom", shownApp: "zoom.us", quitApp: nil))
    }

    // Given a query matching a hidden app that quit since the last read
    // When typing
    // Then no match, naming the app that is not running
    func test_noMatch_namesTheAppThatQuit() {
        let state = model([app("Paste"), app("Dropbox", .alwaysHidden, running: false)], query: "drop")
        XCTAssertEqual(state.content, .noMatch(query: "drop", shownApp: nil, quitApp: "Dropbox"))
    }

    // Given a query that matches nothing anywhere
    // When typing
    // Then plain no match
    func test_noMatch_plain() {
        XCTAssertEqual(model([app("Paste")], query: "xyz").content, .noMatch(query: "xyz", shownApp: nil, quitApp: nil))
    }

    // Given a query that starts one of macOS's keep-list names
    // When nothing hidden matches
    // Then the macOS item state, with the item's name
    func test_macOSItems_getTheirOwnState() {
        XCTAssertEqual(model([app("Paste")], query: "focus").content, .systemItem(name: "Focus"))
        XCTAssertEqual(model([app("Paste")], query: "Sir").content, .systemItem(name: "Siri"))
        XCTAssertEqual(model([app("Paste")], query: "now p").content, .systemItem(name: "Now Playing"))
        // One letter would name too many things.
        XCTAssertEqual(model([app("Paste")], query: "f").content, .noMatch(query: "f", shownApp: nil, quitApp: nil))
    }

    // Given a hidden app that really is called Focus
    // When typing "focus"
    // Then the app wins over the macOS item
    func test_anAppNamedLikeAMacOSItem_isListed() {
        let state = model([app("Focus")], query: "focus")
        XCTAssertEqual(state.rows.map(\.candidate.name), ["Focus"])
    }

    // Given Return found the app but its icon would not press
    // When the palette shows it
    // Then the cannot-open state, until the query changes
    func test_cannotOpen_clearsOnTheNextKeystroke() {
        var state = model([app("Dropbox")], query: "dro")
        state.showCannotOpen(appName: "Dropbox")
        XCTAssertEqual(state.content, .cannotOpen(appName: "Dropbox"))
        state.setQuery("drop")
        XCTAssertEqual(state.rows.map(\.candidate.name), ["Dropbox"])
    }

    // Given presentation mode keeps two apps hidden
    // When the list is built, and the query names one of them
    // Then they are not listed and no hint names them, whichever section they sit in
    func test_sensitiveAppsLeaveTheListWhilePresenting() {
        let environment = PaletteEnvironment(accessibilityTrusted: true, engineAvailable: true,
                                             hiddenWhilePresenting: ["com.test.slack", "com.test.bear", "com.test.dropbox"])
        let apps = [app("Slack"), app("Paste"), app("Bear", .visible), app("Dropbox", .alwaysHidden, running: false)]
        XCTAssertEqual(model(apps, environment: environment).rows.map(\.candidate.name), ["Paste"])
        XCTAssertEqual(model(apps, query: "sla", environment: environment).content,
                       .noMatch(query: "sla", shownApp: nil, quitApp: nil))
        XCTAssertEqual(model(apps, query: "bear", environment: environment).content,
                       .noMatch(query: "bear", shownApp: nil, quitApp: nil), "a shown sensitive app is not named either")
        XCTAssertEqual(model(apps, query: "drop", environment: environment).content,
                       .noMatch(query: "drop", shownApp: nil, quitApp: nil), "nor a quit one")
        XCTAssertEqual(model(apps, query: "sla").rows.map(\.candidate.name), ["Slack"], "off presentation they list as before")
    }

    // MARK: results and selection

    // Given hidden, always hidden, visible and quit apps
    // When the query is empty
    // Then the running hidden ones are listed under a header each
    func test_emptyQuery_groupsBySection() {
        let state = model([app("Paste"), app("Amphetamine", .alwaysHidden), app("Bear", .visible), app("Gone", .hidden, running: false), app("1Password")])
        XCTAssertEqual(state.content, .results([
            .header(.hidden), .row(PaletteRanking.rank(query: "", in: [app("1Password")])[0]),
            .row(PaletteRanking.rank(query: "", in: [app("Paste")])[0]),
            .header(.alwaysHidden), .row(PaletteRanking.rank(query: "", in: [app("Amphetamine", .alwaysHidden)])[0]),
        ]))
    }

    // Given the board's example, "pa"
    // When ranked
    // Then the sections stay together, so their headers show, and the selection starts on Paste
    func test_boardExample_keepsHeadersAndSelectsTheBestMatch() {
        let state = model([app("Amphetamine", .alwaysHidden), app("1Password"), app("Paste")], query: "pa")
        guard case .results(let items) = state.content else { return XCTFail("\(state.content)") }
        XCTAssertEqual(items.map { item -> String in
            switch item {
            case .header(let section): return "# \(section)"
            case .row(let match): return match.candidate.name
            }
        }, ["# hidden", "Paste", "1Password", "# alwaysHidden", "Amphetamine"])
        XCTAssertEqual(state.selected?.name, "Paste")
    }

    // Given a prefix match in always hidden and a weaker one in hidden
    // When ranked
    // Then the prefix match comes first, and each row carries its own section instead of headers
    func test_interleavedSections_dropTheHeaders() {
        let state = model([app("Spaceship", .hidden), app("Pages", .alwaysHidden), app("Paste", .hidden)], query: "pa")
        guard case .results(let items) = state.content else { return XCTFail("\(state.content)") }
        XCTAssertEqual(state.rows.map(\.candidate.name), ["Paste", "Pages", "Spaceship"])
        XCTAssertFalse(items.contains { if case .header = $0 { return true } else { return false } })
    }

    // Given three results
    // When moving the selection past both ends
    // Then it stops at the ends
    func test_selectionStopsAtTheEnds() {
        var state = model([app("Aa"), app("Ab"), app("Ac")], query: "a")
        XCTAssertEqual(state.selected?.name, "Aa")
        state.moveSelection(by: -1)
        XCTAssertEqual(state.selected?.name, "Aa")
        state.moveSelection(by: 1)
        state.moveSelection(by: 1)
        state.moveSelection(by: 1)
        XCTAssertEqual(state.selected?.name, "Ac")
    }

    // Given a moved selection
    // When the query changes
    // Then the selection goes back to the first row
    func test_typing_resetsTheSelection() {
        var state = model([app("Aa"), app("Ab")], query: "a")
        state.moveSelection(by: 1)
        state.setQuery("ab")
        XCTAssertEqual(state.selected?.name, "Ab")
        state.setQuery("a")
        XCTAssertEqual(state.selected?.name, "Aa")
    }

    // Given a selected app
    // When the catalog changes under the open palette
    // Then the same app stays selected, and an app that quit leaves the list
    func test_catalogUpdate_keepsTheSelectionOnTheSameApp() {
        var state = model([app("Aa"), app("Ab"), app("Ac")])
        state.select(bundle: "com.test.ab")
        state.update(candidates: [app("Aa"), app("Ab"), app("Ac"), app("Ad")], environment: ready)
        XCTAssertEqual(state.selected?.name, "Ab")
        state.update(candidates: [app("Aa"), app("Ab", running: false), app("Ac")], environment: ready)
        XCTAssertEqual(state.rows.map(\.candidate.name), ["Aa", "Ac"])
        XCTAssertEqual(state.selected?.name, "Aa")
    }

    // Given no results
    // When moving or reading the selection
    // Then there is none, and nothing crashes
    func test_noResults_noSelection() {
        var state = model([app("Aa")], query: "zzz")
        state.moveSelection(by: 1)
        XCTAssertNil(state.selected)
        XCTAssertEqual(state.rows, [])
    }
}
