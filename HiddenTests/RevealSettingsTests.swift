//
//  RevealSettingsTests.swift
//  HiddenTests
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import XCTest
import AppKit
@testable import Hidden_Bar

/// Contract: the three reveal gestures are opt-in prefs, and the General tab
/// groups them with the hover row under the title the design board gives.
/// Serves: Preferences, PreferencesViewController.
/// Mock boundary: none. Real `AppDefaults.store`; the keys are saved in
/// setUp and put back in tearDown.
final class RevealSettingsTests: XCTestCase {

    private static let keys = [UserDefaults.Key.revealOnScrollEnabled, UserDefaults.Key.revealOnEmptyClickEnabled,
                               UserDefaults.Key.revealOnShakeEnabled]
    private var saved: [String: Any] = [:]
    private var windows: [PreferencesWindowController] = []

    override func setUp() {
        super.setUp()
        for key in Self.keys { saved[key] = AppDefaults.store.object(forKey: key) }
    }

    override func tearDown() {
        for key in Self.keys {
            if let value = saved[key] { AppDefaults.store.set(value, forKey: key) } else { AppDefaults.store.removeObject(forKey: key) }
        }
        windows.removeAll()
        super.tearDown()
    }

    private func texts(build: SettingsBuild) -> [String] {
        var context = SettingsContext.live
        context.build = build
        context.osMajorVersion = 27
        context.statusOverride = .working
        let controller = PreferencesWindowController(context: context)
        windows.append(controller)
        func all(_ view: NSView) -> [NSView] { view.subviews + view.subviews.flatMap(all) }
        return all(controller.pane(.general).view).compactMap { ($0 as? NSTextField)?.stringValue }
    }

    // Given no stored value
    // When reading each reveal pref
    // Then it is off, so 1.13 behaves like 1.12 until the user opts in
    func test_everyRevealPref_isOffByDefault() {
        for key in Self.keys { AppDefaults.store.removeObject(forKey: key) }
        XCTAssertFalse(Preferences.revealOnScrollEnabled)
        XCTAssertFalse(Preferences.revealOnEmptyClickEnabled)
        XCTAssertFalse(Preferences.revealOnShakeEnabled)
    }

    // Given each setter
    // When writing true then false
    // Then the stored value follows under the key's own name, and prefsChanged posts
    func test_setters_roundTripAndPostPrefsChanged() {
        let setters: [(String, (Bool) -> Void, () -> Bool)] = [
            ("revealOnScrollEnabled", { Preferences.revealOnScrollEnabled = $0 }, { Preferences.revealOnScrollEnabled }),
            ("revealOnEmptyClickEnabled", { Preferences.revealOnEmptyClickEnabled = $0 }, { Preferences.revealOnEmptyClickEnabled }),
            ("revealOnShakeEnabled", { Preferences.revealOnShakeEnabled = $0 }, { Preferences.revealOnShakeEnabled }),
        ]
        for (key, write, read) in setters {
            for value in [true, false] {
                let posted = expectation(forNotification: .prefsChanged, object: nil)
                write(value)
                wait(for: [posted], timeout: 1)
                XCTAssertEqual(read(), value, key)
                XCTAssertEqual(AppDefaults.store.bool(forKey: key), value, key)
            }
        }
        XCTAssertEqual(Self.keys, setters.map { $0.0 })
    }

    // Given the direct build
    // When reading the General tab
    // Then the group title and footnote show, and the four rows with their captions follow the board's order
    func test_directGeneralTab_showsTheGroup() {
        let shown = texts(build: .direct)
        for text in ["Also show hidden icons when you", "Clicking anywhere off the menu bar hides them again."] {
            XCTAssertTrue(shown.contains(text), text)
        }
        // Rows sit at one nesting depth, so their order in the walk is their order on screen.
        let rows = ["Rest the pointer on the menu bar", "Scroll down on the menu bar", "Scroll up to hide them again.",
                    "Click empty space in the menu bar", "Shake the pointer at the top of the screen", "Three quick side-to-side moves."]
        let positions = rows.map { shown.firstIndex(of: $0) }
        XCTAssertFalse(positions.contains { $0 == nil }, "missing: \(zip(rows, positions).filter { $0.1 == nil }.map { $0.0 })")
        XCTAssertEqual(positions.compactMap { $0 }.sorted(), positions.compactMap { $0 }, "rows out of board order")
    }

    // Given the App Store build
    // When reading the General tab
    // Then the click row is gone and the rest of the group stays
    func test_appStoreGeneralTab_hidesOnlyTheClickRow() {
        let shown = texts(build: .appStore)
        XCTAssertFalse(shown.contains("Click empty space in the menu bar"))
        for text in ["Also show hidden icons when you", "Rest the pointer on the menu bar", "Scroll down on the menu bar",
                     "Shake the pointer at the top of the screen"] {
            XCTAssertTrue(shown.contains(text), text)
        }
    }

    // Given every locale file
    // When looking for the new strings
    // Then each carries each one
    func test_everyLocale_carriesTheRevealStrings() {
        let keys = ["Also show hidden icons when you", "Rest the pointer on the menu bar", "Scroll down on the menu bar",
                    "Scroll up to hide them again.", "Click empty space in the menu bar",
                    "Shake the pointer at the top of the screen", "Three quick side-to-side moves.",
                    "Clicking anywhere off the menu bar hides them again."]
        let localizations = Bundle.main.localizations.filter { $0 != "Base" }
        XCTAssertGreaterThan(localizations.count, 5)
        for locale in localizations {
            guard let path = Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: locale),
                  let table = NSDictionary(contentsOfFile: path) as? [String: String] else {
                XCTFail("no Localizable.strings for \(locale)")
                continue
            }
            for key in keys { XCTAssertNotNil(table[key], "\(locale) is missing \"\(key)\"") }
        }
    }
}
