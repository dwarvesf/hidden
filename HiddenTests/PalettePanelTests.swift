//
//  PalettePanelTests.swift
//  HiddenTests
//
//  Copyright © 2026 Console Labs. All rights reserved.
//

import XCTest
import AppKit
@testable import Hidden_Bar

#if HIDDENBAR_NATIVE_VISIBILITY

/// Contract: the palette draws each board state with the board's copy, opens an
/// app on Return, moves it on Command-Return and Option-Return, closes on Escape
/// or when it stops being key, and shows the cannot-open state when the icon
/// would not press.
/// Serves: PaletteController, PaletteContentView, PaletteSnapshot.
/// Mock boundary: a fixture catalog (throwaway defaults suite, private
/// notification center, fixture resolver) and a fake host. The panel is built
/// but never ordered onto the screen.
final class PalettePanelTests: XCTestCase {

    private final class FakeResolver: MenuBarAppResolving {
        var running: Set<String> = []
        let names = ["com.paste": "Paste", "com.1password": "1Password", "com.amphetamine": "Amphetamine", "com.zoom": "zoom.us"]
        func name(of bundle: String) -> String? { names[bundle] }
        func icon(of bundle: String) -> NSImage? { NSImage(size: NSSize(width: 16, height: 16)) }
        func isRunning(_ bundle: String) -> Bool { running.contains(bundle) }
    }

    private final class FakeHost {
        var environment = PaletteEnvironment(accessibilityTrusted: true, engineAvailable: true)
        var arrow: CGRect? = CGRect(x: 1300, y: 975, width: 20, height: 25)
        var opened: [String] = []
        var finish: ((PaletteOpenResult) -> Void)?
        var moves: [String] = []
        var accessibilityOpened = 0
        var appsOpened = 0

        var host: PaletteHost {
            PaletteHost(environment: { [unowned self] in environment },
                        arrowFrame: { [unowned self] in arrow },
                        open: { [unowned self] bundle, done in opened.append(bundle); finish = done },
                        move: { [unowned self] section, bundle in moves.append("\(bundle)=\(section)") },
                        openAccessibilitySettings: { [unowned self] in accessibilityOpened += 1 },
                        openMenuBarApps: { [unowned self] in appsOpened += 1 })
        }
    }

    private var suite: String!
    private var defaults: UserDefaults!
    private var center: NotificationCenter!
    private var resolver: FakeResolver!
    private var catalog: MenuBarItemCatalog!
    private var fake: FakeHost!
    private var palette: PaletteController!

    override func setUp() {
        super.setUp()
        suite = "PalettePanelTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        center = NotificationCenter()
        resolver = FakeResolver()
        resolver.running = ["com.paste", "com.1password", "com.amphetamine", "com.zoom"]
        catalog = MenuBarItemCatalog(defaults: defaults, center: center, resolver: resolver, pinnedTable: { [:] })
        catalog.record(layout: MenuBarLayout(sections: ["com.paste": .hidden, "com.1password": .hidden,
                                                         "com.amphetamine": .alwaysHidden, "com.zoom": .visible]), inventory: [])
        fake = FakeHost()
        palette = makePalette()
    }

    override func tearDown() {
        palette.close()
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func makePalette() -> PaletteController {
        let screen = PaletteScreen(frame: CGRect(x: 0, y: 0, width: 1600, height: 1000), visibleFrame: CGRect(x: 0, y: 0, width: 1600, height: 975))
        return PaletteController(host: fake.host, catalog: catalog, screens: { [screen] }, pointer: { CGPoint(x: 100, y: 100) },
                                 notifications: center, ordersPanelFront: false)
    }

    /// Every string the panel shows.
    private var texts: [String] {
        func all(_ view: NSView) -> [NSView] { view.subviews + view.subviews.flatMap(all) }
        guard let content = palette.contentView else { return [] }
        return all(content).compactMap { ($0 as? NSTextField).map { $0.attributedStringValue.string } }
    }

    private func buttons() -> [NSButton] {
        func all(_ view: NSView) -> [NSView] { view.subviews + view.subviews.flatMap(all) }
        return palette.contentView.map { all($0).compactMap { $0 as? NSButton } } ?? []
    }

    // MARK: lists

    // Given the catalog with two hidden apps, one always hidden and one visible
    // When the palette opens
    // Then it lists the hidden ones under headers, each with its bundle id, the first selected; no visible app
    func test_opens_listingHiddenAndAlwaysHiddenApps() {
        palette.show()
        XCTAssertTrue(palette.isVisible)
        XCTAssertTrue(texts.contains("Hidden") && texts.contains("Always hidden"), "a header per section")
        for name in ["1Password", "Paste", "Amphetamine"] { XCTAssertTrue(texts.contains(name), name) }
        for bundle in ["com.paste", "com.1password", "com.amphetamine"] { XCTAssertTrue(texts.contains(bundle), bundle) }
        XCTAssertFalse(texts.contains("zoom.us"))
        XCTAssertTrue(texts.contains("↵ Open"), "the selected row says what Return does")
        XCTAssertEqual(palette.debugState["selected"] as? String, "com.1password")
    }

    // Given the board's query
    // When typing "pa"
    // Then Paste, 1Password and Amphetamine are listed in that order with Paste selected
    func test_typing_filtersAndRanks() {
        palette.show()
        palette.setQuery("pa")
        XCTAssertEqual(palette.debugState["rows"] as? [String], ["com.paste", "com.1password", "com.amphetamine"])
        XCTAssertEqual(palette.debugState["selected"] as? String, "com.paste")
    }

    // Given the key hints of the board
    // When the list shows
    // Then the four hints show
    func test_keyHints() {
        palette.show()
        for hint in ["Open its menu", "Keep shown", "Always hide", "Close"] { XCTAssertTrue(texts.contains(hint), hint) }
    }

    // Given the pinned-sections beta is off (a move would write a table nothing reads)
    // When the list shows, and Command-Return or Option-Return is pressed
    // Then only the open and close hints show, and neither key moves anything
    func test_pinnedSectionsOff_hidesTheMoveHintsAndKeys() {
        fake.environment.pinsSections = false
        palette.show()
        palette.setQuery("pa")
        XCTAssertTrue(texts.contains("Open its menu") && texts.contains("Close"))
        XCTAssertFalse(texts.contains("Keep shown"))
        XCTAssertFalse(texts.contains("Always hide"))

        palette.perform(.keepShown)
        palette.perform(.alwaysHide)
        XCTAssertEqual(fake.moves, [])
        XCTAssertTrue(palette.isVisible, "a refused key leaves the palette open")
    }

    // Given presentation mode is on with Paste and Amphetamine sensitive
    // When the palette opens, and a query names a sensitive app
    // Then they are not listed, and no hint names them
    func test_sensitiveAppsAreLeftOutOfTheListWhilePresenting() {
        fake.environment.hiddenWhilePresenting = ["com.paste", "com.amphetamine"]
        palette.show()
        XCTAssertTrue(texts.contains("1Password"))
        XCTAssertFalse(texts.contains("Paste"))
        XCTAssertFalse(texts.contains("Amphetamine"))
        palette.setQuery("paste")
        let rows = palette.debugState["rows"] as? [String] ?? []
        XCTAssertFalse(rows.contains("com.paste") || rows.contains("com.amphetamine"))
        XCTAssertFalse(texts.contains { $0.contains("Paste") })
    }

    // Given a list that still shows an app presentation mode then keeps hidden
    // When Return reaches the engine and it refuses as sensitive
    // Then the app drops out of the list and nothing names it
    func test_aSensitiveRefusalDropsTheAppWithoutNamingIt() {
        palette.show()
        palette.setQuery("pa")
        palette.perform(.open)
        fake.environment.hiddenWhilePresenting = ["com.paste"]
        fake.finish?(.sensitive)
        XCTAssertFalse(texts.contains { $0.contains("Paste") })
        XCTAssertFalse(texts.contains { $0.contains("stays hidden") })
    }

    // MARK: Return, Command-Return, Option-Return

    // Given "pa" typed
    // When pressing Return
    // Then Paste is opened through the host and the row says so until the host answers, then the palette closes
    func test_return_opensTheSelectedApp() {
        palette.show()
        palette.setQuery("pa")
        palette.perform(.open)
        XCTAssertEqual(fake.opened, ["com.paste"])
        XCTAssertTrue(texts.contains("Opening…"))
        XCTAssertTrue(palette.isVisible)

        fake.finish?(.opened)
        XCTAssertFalse(palette.isVisible)
    }

    // Given a second Return while the first is in flight
    // When it arrives
    // Then the app is not opened twice
    func test_returnTwice_opensOnce() {
        palette.show()
        palette.setQuery("pa")
        palette.perform(.open)
        palette.perform(.open)
        XCTAssertEqual(fake.opened, ["com.paste"])
    }

    // Given the arrow keys
    // When moving down then Return
    // Then the second row opens
    func test_arrowKeys_moveTheSelection() {
        palette.show()
        palette.setQuery("pa")
        palette.perform(.moveDown)
        palette.perform(.open)
        XCTAssertEqual(fake.opened, ["com.1password"])
    }

    // Given Command-Return and Option-Return
    // When pressed on a selected app
    // Then the app moves to visible, or to always hidden, and the palette closes
    func test_commandAndOptionReturn_moveTheApp() {
        palette.show()
        palette.setQuery("pa")
        palette.perform(.keepShown)
        XCTAssertEqual(fake.moves, ["com.paste=visible"])
        XCTAssertFalse(palette.isVisible)

        palette.show()
        palette.setQuery("1pa")
        palette.perform(.alwaysHide)
        XCTAssertEqual(fake.moves, ["com.paste=visible", "com.1password=alwaysHidden"])
        XCTAssertEqual(fake.opened, [])
    }

    // Given Escape, and the panel losing key
    // When either happens
    // Then the palette closes
    func test_escapeAndLosingFocus_close() {
        palette.show()
        palette.perform(.close)
        XCTAssertFalse(palette.isVisible)

        palette.show()
        palette.panel?.onResignKey?()
        XCTAssertFalse(palette.isVisible)
    }

    // Given a click on a row
    // When it lands
    // Then that app opens
    func test_clickingARow_opensIt() {
        palette.show()
        palette.contentView?.onRowClick?("com.amphetamine")
        XCTAssertEqual(fake.opened, ["com.amphetamine"])
    }

    // MARK: edge states

    // Given a press that fails
    // When the host answers noPress
    // Then the palette stays and says the app cannot be opened from here
    func test_anIconThatWillNotPress_showsTheEdgeState() {
        palette.show()
        palette.setQuery("pa")
        palette.perform(.open)
        fake.finish?(.noPress)
        XCTAssertTrue(palette.isVisible)
        XCTAssertTrue(texts.contains("Paste can't be opened from here"))
        XCTAssertFalse(texts.contains("Opening…"))
    }

    // Given an engine that cannot lift one app
    // When the host answers unavailable
    // Then the palette says Hidden Bar is not hiding icons
    func test_engineUnavailable_showsTheEdgeState() {
        palette.show()
        palette.perform(.open)
        fake.finish?(.unavailable)
        XCTAssertTrue(texts.contains("Hidden Bar is not hiding icons right now"))
    }

    // Given no Accessibility
    // When the palette opens and the button is pressed
    // Then the permission state shows and the button opens System Settings
    func test_accessibilityOff_buttonOpensSystemSettings() throws {
        fake.environment.accessibilityTrusted = false
        palette.show()
        XCTAssertTrue(texts.contains("Hidden Bar needs Accessibility access"))
        let button = try XCTUnwrap(buttons().first { $0.title == "Open System Settings" })
        button.performClick(nil)
        XCTAssertEqual(fake.accessibilityOpened, 1)
        XCTAssertFalse(palette.isVisible)
    }

    // Given every app visible
    // When the palette opens
    // Then "nothing is hidden" with a button to Menu Bar Apps
    func test_nothingHidden_buttonOpensMenuBarApps() throws {
        catalog.record(layout: MenuBarLayout(sections: ["com.paste": .visible, "com.1password": .visible, "com.amphetamine": .visible]), inventory: [])
        palette.show()
        XCTAssertTrue(texts.contains("Nothing is hidden right now"))
        let button = try XCTUnwrap(buttons().first { $0.title == "Open Menu Bar Apps" })
        button.performClick(nil)
        XCTAssertEqual(fake.appsOpened, 1)
    }

    // Given a query that matches only a shown app
    // When typing it
    // Then the board's copy names the shown app
    func test_noMatch_copy() {
        palette.show()
        palette.setQuery("zoom")
        XCTAssertTrue(texts.contains("No hidden icon matches \"zoom\""))
        XCTAssertTrue(texts.contains("zoom.us is shown in the menu bar now."))
    }

    // Given a macOS item's name
    // When typing it
    // Then the keep-list copy shows
    func test_macOSItem_copy() {
        palette.show()
        palette.setQuery("focus")
        XCTAssertTrue(texts.contains("Focus can't be opened from here"))
        XCTAssertTrue(texts.contains("macOS hides Focus, Siri and Now Playing whenever Hidden Bar hides icons. Click the arrow to show everything."))
    }

    // Given an app that quit since the last read
    // When the catalog tells the open palette
    // Then its row goes away
    func test_aHiddenAppThatQuit_leavesTheList() {
        palette.show()
        resolver.running.remove("com.paste")
        catalog.refreshRunning()
        XCTAssertFalse(texts.contains("Paste"))
        XCTAssertTrue(texts.contains("1Password"))
    }

    // MARK: live wiring

    // Given the app's own status bar controller, a sensitive set in the preferences
    // When the palette environment is read with presentation mode on, then off
    // Then the live wiring hands the sensitive list over only while presenting, and the pinned-sections switch follows the preference
    func test_liveEnvironmentCarriesTheSensitiveListOnlyWhilePresenting() throws {
        let bar = try XCTUnwrap((NSApp.delegate as? AppDelegate)?.statusBarController, "the test host owns the status bar controller")
        let keys = [UserDefaults.Key.presentationSensitiveApps, UserDefaults.Key.pinnedSectionsEnabled]
        let saved = keys.map { AppDefaults.store.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { AppDefaults.store.set(value, forKey: key) } else { AppDefaults.store.removeObject(forKey: key) }
            }
            bar.presentingOverride = nil
        }
        Preferences.presentationSensitiveApps = ["com.paste", "com.1password"]
        Preferences.pinnedSectionsEnabled = false

        bar.presentingOverride = true
        XCTAssertEqual(bar.paletteEnvironment().hiddenWhilePresenting, ["com.paste", "com.1password"])
        XCTAssertFalse(bar.paletteEnvironment().pinsSections)

        bar.presentingOverride = false
        XCTAssertEqual(bar.paletteEnvironment().hiddenWhilePresenting, [])
    }

    // MARK: placement

    // Given an arrow on the display with the pointer
    // When the palette opens
    // Then the panel sits under it, inside the screen
    func test_panelOpensUnderTheArrow() throws {
        palette.show()
        let frame = try XCTUnwrap(palette.panel?.frame)
        XCTAssertEqual(frame.midX, 1310, accuracy: 1)
        XCTAssertEqual(frame.maxY, 975 - PalettePlacement.gapBelowMenuBar, accuracy: 1)
        XCTAssertEqual(frame.width, PaletteContentView.width, accuracy: 1)
    }

    // MARK: snapshots

    // Given the fixture scenes
    // When rendering
    // Then every state of the boards has a light and a dark png, plus the General tab
    func test_snapshotsWriteEveryState() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PaletteSnapshot-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        PaletteSnapshot.render(to: dir, build: "direct")
        let written = Set(try FileManager.default.contentsOfDirectory(atPath: dir.path))
        for mode in ["light", "dark"] {
            for scene in PaletteSnapshot.scenes {
                XCTAssertTrue(written.contains("direct-palette-\(scene.name)-\(mode).png"), "\(scene.name) \(mode)")
            }
            XCTAssertTrue(written.contains("direct-palette-settings-\(mode).png"))
        }
        XCTAssertEqual(Set(PaletteSnapshot.scenes.map(\.name)),
                       ["results", "all", "opening", "nomatch", "nothinghidden", "accessibilityoff", "macositem", "appquit", "cannotopen", "presenting", "nopins", "enginedown"])
    }
}
#endif
