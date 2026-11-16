//
//  PaletteSettingsTests.swift
//  HiddenTests
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import XCTest
import AppKit
@testable import Hidden_Bar

/// Contract: the find shortcut is one Data preference, unset by default (the
/// feature is off), recorded by a row under "Keyboard shortcut" on the General
/// tab of the direct build on macOS 27 only, and every locale carries its text.
/// Serves: Preferences, PreferencesViewController.
/// Mock boundary: none. Real `AppDefaults.store` for the one key, saved in
/// setUp and put back in tearDown; the registry is the real one.
final class PaletteSettingsTests: XCTestCase {

    private let key = UserDefaults.Key.findHiddenIconShortcut
    private var saved: Any?
    private var windows: [PreferencesWindowController] = []

    override func setUp() {
        super.setUp()
        saved = AppDefaults.store.object(forKey: key)
        AppDefaults.store.removeObject(forKey: key)
    }

    override func tearDown() {
        if let saved { AppDefaults.store.set(saved, forKey: key) } else { AppDefaults.store.removeObject(forKey: key) }
        windows.removeAll()
        super.tearDown()
    }

    private func general(build: SettingsBuild, os: Int) -> NSView {
        var context = SettingsContext.live
        context.build = build
        context.osMajorVersion = os
        context.statusOverride = .working
        let controller = PreferencesWindowController(context: context)
        windows.append(controller)
        controller.window?.layoutIfNeeded()
        return controller.pane(.general).view
    }

    private func views(build: SettingsBuild, os: Int) -> [NSView] {
        func all(_ view: NSView) -> [NSView] { view.subviews + view.subviews.flatMap(all) }
        return all(general(build: build, os: os))
    }

    private func recorder(in views: [NSView]) -> NSButton? {
        return views.compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == key }
    }

    private func option(key: String = "k") -> GlobalKeybindPreferences {
        return GlobalKeybindPreferences(function: false, control: false, command: true, shift: false, option: true,
                                        capsLock: false, carbonFlags: 2304, characters: key, keyCode: 40)
    }

    // Given no stored value
    // When reading the preference
    // Then it is nil, so the palette is off until the user records a shortcut
    func test_unsetByDefault() {
        XCTAssertNil(Preferences.findHiddenIconShortcut)
        XCTAssertNil(AppDefaults.store.object(forKey: key))
    }

    // Given a shortcut
    // When writing it, then nil
    // Then it is stored as GlobalKeybindPreferences JSON under findHiddenIconShortcut and cleared again, and prefsChanged posts both times
    func test_setterRoundTripsAndPostsPrefsChanged() throws {
        let posted = expectation(forNotification: .prefsChanged, object: nil)
        posted.expectedFulfillmentCount = 2
        Preferences.findHiddenIconShortcut = option()
        let data = try XCTUnwrap(AppDefaults.store.data(forKey: "findHiddenIconShortcut"))
        XCTAssertEqual(try JSONDecoder().decode(GlobalKeybindPreferences.self, from: data), option())
        XCTAssertEqual(Preferences.findHiddenIconShortcut, option())

        Preferences.findHiddenIconShortcut = nil
        XCTAssertNil(AppDefaults.store.object(forKey: key))
        wait(for: [posted], timeout: 1)
    }

    // Given the direct build on macOS 27
    // When reading the General tab
    // Then the row, its caption and a recorder carrying the key sit under "Keyboard shortcut" and above the reveal group
    func test_directGeneralTab_hasTheRowUnderTheKeyboardShortcut() {
        let pane = general(build: .direct, os: 27)
        func all(_ view: NSView) -> [NSView] { view.subviews + view.subviews.flatMap(all) }
        XCTAssertNotNil(recorder(in: all(pane)), "the recorder's button carries the preference key")
        // Top of each label on screen, from the pane's own coordinates.
        func tops(_ text: String) -> [CGFloat] {
            let labels = all(pane).compactMap { $0 as? NSTextField }.filter { $0.stringValue == text }
            return labels.map { label in
                let frame = pane.convert(label.bounds, from: label)
                return pane.isFlipped ? frame.minY : -frame.maxY
            }
        }
        func top(_ text: String) -> CGFloat? { tops(text).first }
        let caption = "Opens a search under the arrow. Type a few letters, then press Return to open that app's menu."
        // "Keyboard shortcut" is also the status card's and the Presentation mode group's:
        // the row is the one just above "Find a hidden icon".
        let findTop = top("Find a hidden icon")
        let shortcutTop = findTop.flatMap { find in tops("Keyboard shortcut").filter { $0 < find }.max() }
        let order: [(String, CGFloat?)] = [("Keyboard shortcut", shortcutTop), ("Find a hidden icon", findTop),
                                           (caption, top(caption)), ("Also show hidden icons when you", top("Also show hidden icons when you"))]
        XCTAssertFalse(order.contains { $0.1 == nil }, "missing: \(order.filter { $0.1 == nil }.map { $0.0 })")
        let tops = order.compactMap { $0.1 }
        XCTAssertEqual(tops, tops.sorted(), "rows out of board order")
        XCTAssertLessThan(tops[1] - tops[0], 60, "directly under the existing shortcut row")
    }

    // Given a build or OS without the native engine
    // When reading the General tab
    // Then there is no recorder: the palette lists apps from Accessibility, which only the native engine reads
    func test_otherBuildsHaveNoRow() {
        XCTAssertNil(recorder(in: views(build: .appStore, os: 27)))
        XCTAssertNil(recorder(in: views(build: .appStore, os: 26)))
        XCTAssertNil(recorder(in: views(build: .direct, os: 26)))
    }

    // Given the recorder
    // When its stored shortcut changes, and when it is cleared
    // Then it shows the stored combination, and clearing removes the key
    func test_recorderShowsAndClearsTheStoredShortcut() throws {
        Preferences.findHiddenIconShortcut = option()
        var context = SettingsContext.live
        context.build = .direct
        context.osMajorVersion = 27
        context.statusOverride = .working
        let controller = PreferencesWindowController(context: context)
        windows.append(controller)
        let general = try XCTUnwrap(controller.pane(.general) as? PreferencesViewController)
        let row = try XCTUnwrap(general.findShortcutRecorder)
        XCTAssertEqual(row.button.title, option().description)
        row.clear()
        XCTAssertNil(AppDefaults.store.object(forKey: key))
        XCTAssertEqual(row.button.title, "Set Shortcut".localized)
    }

    // Given a fixture suite for snapshots
    // When the pane builds
    // Then the recorder reads the suite and the real preference stays untouched
    func test_fixtureDefaults_leaveTheRealPreferenceAlone() throws {
        let suite = "PaletteSettingsTests.\(UUID().uuidString)"
        let fixture = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { fixture.removePersistentDomain(forName: suite) }
        fixture.set(try JSONEncoder().encode(option()), forKey: key)
        var context = SettingsContext.live
        context.build = .direct
        context.osMajorVersion = 27
        context.statusOverride = .working
        context.shortcutFixtureDefaults = fixture
        let controller = PreferencesWindowController(context: context)
        windows.append(controller)
        let general = try XCTUnwrap(controller.pane(.general) as? PreferencesViewController)
        XCTAssertEqual(general.findShortcutRecorder?.button.title, option().description)
        XCTAssertNil(AppDefaults.store.object(forKey: key))
    }

    // Given every locale file
    // When looking for the palette strings
    // Then each carries each one
    func test_everyLocale_carriesThePaletteStrings() {
        let keys = ["Find a hidden icon", "Opens a search under the arrow. Type a few letters, then press Return to open that app's menu.",
                    "Find a Hidden Icon...", "Open", "Opening…", "Open its menu", "Keep shown", "Always hide", "Close",
                    "Hidden", "Always hidden", "%@ is shown in the menu bar now.", "%@ is not running.",
                    "Only hidden icons are listed. Shown icons are already one click away.", "No hidden icon matches \"%@\"",
                    "Nothing is hidden right now", "Hold ⌘ and drag an icon left of the arrow, or pick sections in Settings.",
                    "Open Menu Bar Apps", "Hidden Bar needs Accessibility access",
                    "It reads which apps are in the menu bar and opens their menus. It never reads what is on your screen.",
                    "Open System Settings", "%@ can't be opened from here",
                    "macOS hides Focus, Siri and Now Playing whenever Hidden Bar hides icons. Click the arrow to show everything.",
                    "Hidden Bar is not hiding icons right now",
                    "Every icon is already in the menu bar, so there is nothing to find. Open Settings to see why.",
                    "Its icon does not answer Accessibility. Click the arrow to show everything, then click its icon."]
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
