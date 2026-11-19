//
//  LocaleCoverageTests.swift
//  HiddenTests
//
//  Copyright © 2026 Console Labs. All rights reserved.
//

import XCTest
import Foundation

/// Contract: every shipped locale has exactly the English keys, a real
/// translation for each (not the English text), and the same format
/// placeholders. A key that is only present, with English text in it, shipped
/// untranslated for two releases before this test existed.
/// Serves: every `*.lproj/Localizable.strings` except `en` and `Base`.
/// Mock boundary: none. Reads the strings the host app bundle ships, the same
/// way the other locale tests do.
///
/// Adding a string: add the key to every locale in the same commit, translated.
/// If the translation is truly identical to English, list it in
/// `sameInEveryLocale` or `sameInLocale` below with a reason.
final class LocaleCoverageTests: XCTestCase {

    /// Product names and symbols that read the same in every locale.
    static let sameInEveryLocale: [String: String] = [
        "macOS": "product name",
        "Wi-Fi": "product name",
        "Mac App Store": "product name",
        "OK": "international button label",
    ]

    /// True cognates: the translation is the English word. locale, then key, then why.
    static let sameInLocale: [String: [String: String]] = [
        "de": ["Version": "German uses the same word"],
        "fr": ["Version": "French uses the same word",
               "Photos": "French uses the same word",
               "Visible": "French uses the same word",
               "Chevron": "French uses the same word"],
        "it": ["Email": "Italian uses the same word"],
        "pl": ["Separator": "Polish uses the same word"],
        "vi": ["Email": "Vietnamese uses the same word"],
    ]

    /// Keys whose translation lays out its line breaks differently on purpose,
    /// so the "\n" count may differ. Format specifiers are still compared.
    static let newlineLayoutDiffers: [String: [String: String]] = [
        "ar": ["Tutorial text": "paragraph breaks follow Arabic layout"],
        "fr": ["Tutorial text": "paragraph breaks follow French layout"],
        "it": ["Tutorial text": "paragraph breaks follow Italian layout"],
        "ja": ["Tutorial text": "paragraph breaks follow Japanese layout"],
        "tr": ["Tutorial text": "paragraph breaks follow Turkish layout"],
        "zh-Hans": ["Tutorial text": "paragraph breaks follow Chinese layout"],
        "zh-Hant": ["Tutorial text": "paragraph breaks follow Chinese layout",
                    "Tutorial text (arrow boundary)": "paragraph breaks follow Chinese layout"],
    ]

    // MARK: loading

    private static func table(_ locale: String) throws -> [String: String] {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: locale),
                                 "no Localizable.strings for \(locale)")
        return try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String], "\(locale) Localizable.strings does not parse")
    }

    private static func translatedLocales() -> [String] {
        Bundle.main.localizations.filter { $0 != "Base" && $0 != "en" }.sorted()
    }

    private func forEachLocale(_ body: (_ locale: String, _ english: [String: String], _ table: [String: String]) -> Void) throws {
        let english = try Self.table("en")
        XCTAssertFalse(english.isEmpty, "English Localizable.strings is empty")
        let locales = Self.translatedLocales()
        XCTAssertGreaterThan(locales.count, 5)
        for locale in locales {
            body(locale, english, try Self.table(locale))
        }
    }

    // MARK: tests

    // Given the English strings
    // When looking at every other locale's Localizable.strings
    // Then each has exactly the English keys: none missing, none left over
    func test_everyLocale_hasExactlyTheEnglishKeys() throws {
        try forEachLocale { locale, english, table in
            for key in Set(english.keys).subtracting(table.keys).sorted() {
                XCTFail("\(locale) is missing \"\(key)\". Add it to \(locale).lproj/Localizable.strings, translated.")
            }
            for key in Set(table.keys).subtracting(english.keys).sorted() {
                XCTFail("\(locale) has \"\(key)\" but en does not. Remove it from \(locale).lproj/Localizable.strings, or add it to en.")
            }
        }
    }

    // Given the English strings
    // When looking at every other locale's value for each key
    // Then it differs from the English text, unless the key is on the allow-list
    func test_everyLocale_translatesEveryString() throws {
        try forEachLocale { locale, english, table in
            let allowed = Self.sameInLocale[locale] ?? [:]
            for (key, englishValue) in english.sorted(by: { $0.key < $1.key }) {
                guard table[key] == englishValue else { continue }
                if Self.sameInEveryLocale[key] != nil || allowed[key] != nil { continue }
                XCTFail("\(locale) \"\(key)\" is still the English text. Translate it in \(locale).lproj/Localizable.strings, "
                        + "or, if it is identical on purpose, add it to LocaleCoverageTests.sameInLocale[\"\(locale)\"] with a reason.")
            }
        }
    }

    // Given the English strings
    // When looking at every other locale's value for each key
    // Then it carries the same format specifiers and line breaks, the same number of times
    func test_everyLocale_keepsFormatPlaceholders() throws {
        try forEachLocale { locale, english, table in
            let layoutKeys = Self.newlineLayoutDiffers[locale] ?? [:]
            for (key, englishValue) in english.sorted(by: { $0.key < $1.key }) {
                guard let value = table[key] else { continue }
                var want = Self.tokens(in: englishValue)
                var got = Self.tokens(in: value)
                if layoutKeys[key] != nil {
                    want["\n"] = nil
                    got["\n"] = nil
                }
                guard want != got else { continue }
                XCTFail("\(locale) \"\(key)\" changes its placeholders: en has \(Self.describe(want)), \(locale) has \(Self.describe(got)). "
                        + "Fix the translation in \(locale).lproj/Localizable.strings, or, for a line-break layout that differs on purpose, "
                        + "add the key to LocaleCoverageTests.newlineLayoutDiffers[\"\(locale)\"] with a reason.")
            }
        }
    }

    // MARK: placeholders

    private static let tokenPattern = try! NSRegularExpression(pattern: "%(?:\\d+\\$)?(?:l|ll)?[@dDiufsScC%]|\\n")

    private static func tokens(in value: String) -> [String: Int] {
        var counts: [String: Int] = [:]
        let text = value as NSString
        for match in tokenPattern.matches(in: value, range: NSRange(location: 0, length: text.length)) {
            counts[text.substring(with: match.range), default: 0] += 1
        }
        return counts
    }

    private static func describe(_ counts: [String: Int]) -> String {
        if counts.isEmpty { return "none" }
        return counts.sorted { $0.key < $1.key }
            .map { "\($0.value) x \($0.key == "\n" ? "\\n" : $0.key)" }
            .joined(separator: ", ")
    }
}
