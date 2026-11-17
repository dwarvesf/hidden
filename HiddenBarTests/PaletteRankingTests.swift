//
//  PaletteRankingTests.swift
//  HiddenBarTests
//
//  Copyright © 2026 Console Labs. All rights reserved.
//

import XCTest

/// Contract: the palette filters hidden apps by name or bundle id, case and
/// accents aside, and puts the best match first: name start, word start,
/// inside the name, letters in order, bundle id.
/// Serves: PaletteRanking.
/// Mock boundary: none. Plain fixtures.
final class PaletteRankingTests: XCTestCase {

    private func app(_ name: String, _ bundle: String? = nil, section: MenuBarSection = .hidden,
                     running: Bool = true) -> PaletteCandidate {
        return PaletteCandidate(bundleIdentifier: bundle ?? "com.test.\(name.lowercased().replacingOccurrences(of: " ", with: ""))",
                                name: name, section: section, isRunning: running)
    }

    private func names(_ query: String, _ candidates: [PaletteCandidate]) -> [String] {
        return PaletteRanking.rank(query: query, in: candidates).map(\.candidate.name)
    }

    // Given apps whose names match "pa" in every way the board lists
    // When ranking "pa"
    // Then name start, word start, inside the name, letters in order, then bundle id
    func test_everyKindOfMatch_isRankedInTheBoardOrder() {
        let candidates = [
            app("Amphetamine"),                        // letters p...a in order
            app("1Password"),                          // inside the name
            app("Quick Paste"),                        // word start
            app("Paste"),                              // name start
            app("Notes", "com.pa.notes"),              // bundle id only
            app("Calendar"),                           // no match
        ]
        let ranked = PaletteRanking.rank(query: "pa", in: candidates)
        XCTAssertEqual(ranked.map(\.candidate.name), ["Paste", "Quick Paste", "1Password", "Amphetamine", "Notes"])
        XCTAssertEqual(ranked.map(\.kind), [.namePrefix, .wordPrefix, .nameContains, .letters, .bundleIdentifier])
    }

    // Given the same query in capitals and with accents in the name
    // When ranking
    // Then case and accents do not matter
    func test_caseAndAccentsAreIgnored() {
        let candidates = [app("Café Menu"), app("PASTE")]
        XCTAssertEqual(names("CAFE", candidates), ["Café Menu"])
        XCTAssertEqual(names("paste", candidates), ["PASTE"])
        XCTAssertEqual(names("café", candidates), ["Café Menu"])
    }

    // Given a name that has the query at its start and also inside
    // When ranking
    // Then the characters to bold are the first ones
    func test_highlightsFollowTheMatchedCharacters() {
        let candidates = [app("Paste"), app("1Password"), app("Amphetamine"), app("Quick Paste")]
        let byName = Dictionary(uniqueKeysWithValues: PaletteRanking.rank(query: "pa", in: candidates).map { ($0.candidate.name, $0.highlighted) })
        XCTAssertEqual(byName["Paste"], [0, 1])
        XCTAssertEqual(byName["1Password"], [1, 2])
        XCTAssertEqual(byName["Quick Paste"], [6, 7])
        XCTAssertEqual(byName["Amphetamine"], [2, 6], "p of Amphet, a of amine")
    }

    // Given two apps of the same kind in different sections and names
    // When ranking
    // Then hidden comes before always hidden, then the name decides
    func test_sameKind_ordersBySectionThenName() {
        let candidates = [app("Pasta", section: .alwaysHidden), app("Paste", section: .hidden), app("Pace", section: .hidden)]
        XCTAssertEqual(names("pa", candidates), ["Pace", "Paste", "Pasta"])
    }

    // Given an empty or blank query
    // When ranking
    // Then every app is listed, hidden first, by name
    func test_emptyQueryListsEveryone() {
        let candidates = [app("Zoom", section: .alwaysHidden), app("Bear"), app("Alfred")]
        XCTAssertEqual(names("", candidates), ["Alfred", "Bear", "Zoom"])
        XCTAssertEqual(names("   ", candidates), ["Alfred", "Bear", "Zoom"])
        XCTAssertTrue(PaletteRanking.rank(query: "", in: candidates).allSatisfy { $0.kind == nil && $0.highlighted.isEmpty })
    }

    // Given a query no name or bundle id contains, in order
    // When ranking
    // Then nothing is returned
    func test_noMatch_returnsNothing() {
        XCTAssertEqual(names("zzz", [app("Paste"), app("Bear")]), [])
        // Letters must come in order.
        XCTAssertEqual(names("ap", [app("Paste")]), [])
    }

    // Given a query with a space
    // When ranking by letters
    // Then the space is skipped, and a name containing the words matches as typed
    func test_spaces_matchWordsAndSkipInLetterMatches() {
        XCTAssertEqual(names("quick p", [app("Quick Paste")]), ["Quick Paste"])
        XCTAssertEqual(names("now p", [app("Now Playing Tool")]), ["Now Playing Tool"])
        XCTAssertEqual(names("q p", [app("Quick Paste")]), ["Quick Paste"], "letters q and p, space skipped")
    }

    // Given the bundle id has the query but the name does not
    // When ranking
    // Then it matches last, with nothing to bold
    func test_bundleIdMatch_hasNoHighlight() {
        let ranked = PaletteRanking.rank(query: "tinyspeck", in: [app("Slack", "com.tinyspeck.slackmacgap")])
        XCTAssertEqual(ranked.count, 1)
        XCTAssertEqual(ranked.first?.kind, .bundleIdentifier)
        XCTAssertEqual(ranked.first?.highlighted, [])
    }

    // Given an app that quit
    // When asking whether the palette may list it
    // Then only a running hidden or always hidden app counts
    func test_findable_needsARunningHiddenApp() {
        XCTAssertTrue(app("A", section: .hidden).isFindable)
        XCTAssertTrue(app("A", section: .alwaysHidden).isFindable)
        XCTAssertFalse(app("A", section: .visible).isFindable)
        XCTAssertFalse(app("A", section: .hidden, running: false).isFindable)
    }
}
