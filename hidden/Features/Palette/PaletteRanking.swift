//
//  PaletteRanking.swift
//  Hidden Bar
//
//  Copyright © 2026 Console Labs. All rights reserved.
//

import Foundation

/// One app the palette can list: the part of a catalog entry that ranking and
/// state need, free of AppKit so both test bundles can check it.
struct PaletteCandidate: Equatable {
    let bundleIdentifier: String
    let name: String
    let section: MenuBarSection
    let isRunning: Bool

    /// Hidden or always hidden, and still running: the apps a user can look for here.
    /// A stale catalog can still list an app that quit since the last read.
    var isFindable: Bool {
        return section != .visible && isRunning
    }
}

/// How a query matched, best first. The order is the ranking.
enum PaletteMatchKind: Int, Comparable {
    /// The name starts with the query.
    case namePrefix
    /// A word inside the name starts with the query.
    case wordPrefix
    /// The query sits inside the name, not at a word start.
    case nameContains
    /// The query's letters appear in the name in order, with gaps.
    case letters
    /// Only the bundle id contains the query.
    case bundleIdentifier

    static func < (lhs: PaletteMatchKind, rhs: PaletteMatchKind) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

struct PaletteMatch: Equatable {
    let candidate: PaletteCandidate
    let kind: PaletteMatchKind?
    /// Offsets of the characters of `candidate.name` the query matched, for bold type.
    let highlighted: [Int]
}

enum PaletteRanking {
    /// The candidates `query` matches, best first: name start, then a word start,
    /// then inside the name, then letters in order, then the bundle id. Case and
    /// accents do not matter. Within one kind the section (hidden before always
    /// hidden) and then the name decide. An empty query lists everyone, grouped by
    /// section.
    static func rank(query rawQuery: String, in candidates: [PaletteCandidate]) -> [PaletteMatch] {
        let query = fold(rawQuery.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !query.isEmpty else {
            return candidates.map { PaletteMatch(candidate: $0, kind: nil, highlighted: []) }.sorted { order($0, $1) }
        }
        return candidates.compactMap { match($0, query: query) }.sorted {
            if $0.kind != $1.kind { return ($0.kind ?? .bundleIdentifier) < ($1.kind ?? .bundleIdentifier) }
            return order($0, $1)
        }
    }

    private static func order(_ lhs: PaletteMatch, _ rhs: PaletteMatch) -> Bool {
        if lhs.candidate.section != rhs.candidate.section { return lhs.candidate.section < rhs.candidate.section }
        let byName = lhs.candidate.name.localizedCaseInsensitiveCompare(rhs.candidate.name)
        if byName != .orderedSame { return byName == .orderedAscending }
        return lhs.candidate.bundleIdentifier < rhs.candidate.bundleIdentifier
    }

    private static func match(_ candidate: PaletteCandidate, query: [String]) -> PaletteMatch? {
        let name = fold(candidate.name)
        if name.starts(with: query) {
            return PaletteMatch(candidate: candidate, kind: .namePrefix, highlighted: Array(0..<query.count))
        }
        if let start = wordStart(of: query, in: name) {
            return PaletteMatch(candidate: candidate, kind: .wordPrefix, highlighted: Array(start..<start + query.count))
        }
        if let start = firstIndex(of: query, in: name) {
            return PaletteMatch(candidate: candidate, kind: .nameContains, highlighted: Array(start..<start + query.count))
        }
        if let offsets = letters(of: query, in: name) {
            return PaletteMatch(candidate: candidate, kind: .letters, highlighted: offsets)
        }
        if firstIndex(of: query, in: fold(candidate.bundleIdentifier)) != nil {
            return PaletteMatch(candidate: candidate, kind: .bundleIdentifier, highlighted: [])
        }
        return nil
    }

    /// Lower case and without accents, one string per character so offsets
    /// into the folded text are offsets into the name.
    static func fold(_ text: String) -> [String] {
        return text.map { String($0).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
    }

    private static func firstIndex(of query: [String], in text: [String]) -> Int? {
        guard !query.isEmpty, text.count >= query.count else { return nil }
        return (0...text.count - query.count).first { Array(text[$0..<$0 + query.count]) == query }
    }

    private static func wordStart(of query: [String], in text: [String]) -> Int? {
        guard !query.isEmpty, text.count >= query.count else { return nil }
        return (1...max(text.count - query.count, 1)).first { start in
            start + query.count <= text.count
                && isWordBoundary(text[start - 1])
                && Array(text[start..<start + query.count]) == query
        }
    }

    private static func isWordBoundary(_ character: String) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        return !CharacterSet.alphanumerics.contains(scalar)
    }

    /// The first characters of `text` that spell `query` in order, spaces in the query ignored.
    private static func letters(of query: [String], in text: [String]) -> [Int]? {
        var offsets: [Int] = []
        var position = 0
        for letter in query where letter != " " {
            guard let found = text[position...].firstIndex(of: letter) else { return nil }
            offsets.append(found)
            position = found + 1
        }
        return offsets.isEmpty ? nil : offsets
    }
}
