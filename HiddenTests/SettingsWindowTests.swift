//
//  SettingsWindowTests.swift
//  HiddenTests
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import XCTest
import AppKit
@testable import Hidden_Bar

/// Contract: the redesigned Settings window still reads and writes every
/// preference the old storyboard window did, under the same keys, and shows the
/// panes and status card each build should.
/// Serves: PreferencesWindowController, the four panes, StatusCardView.
/// Mock boundary: none. Real `UserDefaults.standard`; every key the window can
/// write is saved in setUp and put back in tearDown.
final class SettingsWindowTests: XCTestCase {

    /// Every key the old Settings window bound to a control. Written out by
    /// hand on purpose: dropping a row from the new window fails a test here.
    static let legacyBoolKeys = [
        UserDefaults.Key.isAutoStart,                      // Start Hidden Bar when I log in
        UserDefaults.Key.isShowPreference,                 // Show preferences on launch
        UserDefaults.Key.alwaysHiddenSectionEnabled,       // Enable always hidden section
        UserDefaults.Key.useFullStatusBarOnExpandEnabled,  // Use the full MenuBar on expanding
        UserDefaults.Key.stealthExpandIconEnabled,         // Fade the arrow while collapsed
        UserDefaults.Key.hoverToExpand,                    // Expand the bar when the pointer rests...
        UserDefaults.Key.notchOverflowEnabled,             // Enable Notch Overflow (notch Macs)
        UserDefaults.Key.pauseHidingForUnkeepableItems,    // macOS 27 direct only
        UserDefaults.Key.showWholeBarWhenCaptureStarts,    // macOS 27 direct only
        UserDefaults.Key.pinnedSectionsEnabled,            // Pinned sections (beta), macOS 27 direct only
        "SUEnableAutomaticChecks",                         // Sparkle, direct only
    ]
    static let legacyOtherKeys = [
        UserDefaults.Key.isAutoHide, UserDefaults.Key.numberOfSecondForAutoHide, // checkbox + delay popup
        UserDefaults.Key.arrowStyle,                                              // arrow style popup
        UserDefaults.Key.globalKey,                                               // global shortcut
        UserDefaultsPinnedSections.key,                                           // Menu Bar Apps section popups (beta)
    ]

    private var saved: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        for key in Self.legacyBoolKeys + Self.legacyOtherKeys {
            saved[key] = UserDefaults.standard.object(forKey: key)
        }
        // The app registers the pane at launch; each test decides.
        MenuBarAppsPane.makeViewController = nil
    }

    override func tearDown() {
        for key in Self.legacyBoolKeys + Self.legacyOtherKeys {
            if let value = saved[key] {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        MenuBarAppsPane.makeViewController = nil
        windows.removeAll()
        super.tearDown()
    }

    // The fullest window: direct build on macOS 27 on a Mac with a notch.
    private func fullContext(_ status: SettingsStatus? = .working) -> SettingsContext {
        var context = SettingsContext.live
        context.build = .direct
        context.osMajorVersion = 27
        context.hasNotch = true
        context.statusOverride = status
        return context
    }

    /// The panes are the controls' targets; keep their window controller alive for the test.
    private var windows: [PreferencesWindowController] = []

    private func allViews(_ controller: PreferencesWindowController) -> [NSView] {
        windows.append(controller)
        return controller.tabs.flatMap { Self.subviews(of: controller.pane($0).view) }
    }

    private static func subviews(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap { subviews(of: $0) }
    }

    private func control(_ key: String, in views: [NSView]) -> NSControl? {
        views.compactMap { $0 as? NSControl }.first { $0.identifier?.rawValue == key }
    }

    /// A click as the user makes it: the switch flips, then sends its action.
    private func click(_ control: NSControl) {
        if let toggle = control as? NSSwitch {
            toggle.state = toggle.state == .on ? .off : .on
            toggle.sendAction(toggle.action, to: toggle.target)
        } else {
            control.performClick(nil)
        }
    }

    // MARK: pref keys

    // Given the fullest Settings window
    // When clicking the control bound to each old on/off key, twice
    // Then the stored value flips and flips back, under the same key as before
    func test_everyOldSwitch_stillWritesItsKey() {
        let views = allViews(PreferencesWindowController(context: fullContext()))
        for key in Self.legacyBoolKeys {
            guard let toggle = control(key, in: views) else {
                XCTFail("no control writes \(key) any more")
                continue
            }
            let before = UserDefaults.standard.bool(forKey: key)
            click(toggle)
            XCTAssertEqual(UserDefaults.standard.bool(forKey: key), !before, "\(key) did not change")
            XCTAssertEqual((toggle as? NSSwitch)?.state == .on, !before, "\(key) switch shows the wrong state")
            click(toggle)
            XCTAssertEqual(UserDefaults.standard.bool(forKey: key), before, "\(key) did not change back")
        }
    }

    // Given the "Hide icons again" popup
    // When picking a delay, then Never
    // Then the delay sets isAutoHide and numberOfSecondForAutoHide, and Never turns
    //      auto-hide off but keeps the delay, as the old checkbox did
    func test_hideIconsAgain_writesTheOldPair() throws {
        let views = allViews(PreferencesWindowController(context: fullContext()))
        let popup = try XCTUnwrap(control(UserDefaults.Key.isAutoHide, in: views) as? NSPopUpButton)

        popup.selectItem(at: AutoHideChoice.after(seconds: 30).index)
        popup.sendAction(popup.action, to: popup.target)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: UserDefaults.Key.isAutoHide))
        XCTAssertEqual(UserDefaults.standard.double(forKey: UserDefaults.Key.numberOfSecondForAutoHide), 30)

        popup.selectItem(at: AutoHideChoice.never.index)
        popup.sendAction(popup.action, to: popup.target)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: UserDefaults.Key.isAutoHide))
        XCTAssertEqual(UserDefaults.standard.double(forKey: UserDefaults.Key.numberOfSecondForAutoHide), 30)

        // The menu's toggle writes isAutoHide elsewhere; the popup follows.
        Preferences.isAutoHide = true
        XCTAssertEqual(popup.indexOfSelectedItem, AutoHideChoice.after(seconds: 30).index)
    }

    // Given the Appearance tiles
    // When clicking each
    // Then arrowStyle stores that style's name, as the old popup did
    func test_arrowTiles_writeArrowStyle() {
        let views = allViews(PreferencesWindowController(context: fullContext()))
        for style in ArrowStyle.allCases {
            guard let tile = control(AppearanceSettingsViewController.tileIdentifierPrefix + style.rawValue, in: views) else {
                XCTFail("no tile for \(style)")
                continue
            }
            click(tile)
            XCTAssertEqual(UserDefaults.standard.string(forKey: UserDefaults.Key.arrowStyle), style.rawValue)
            XCTAssertTrue((tile as? ArrowStyleTile)?.isSelected ?? false)
        }
    }

    // Given a stored global shortcut
    // When the window loads, then the shortcut is cleared
    // Then the recorder shows it, and clearing removes globalKey
    func test_shortcutRecorder_readsAndClearsGlobalKey() throws {
        let key = GlobalKeybindPreferences(function: false, control: false, command: true, shift: true, option: false,
                                           capsLock: false, carbonFlags: 0, characters: "k", keyCode: 40)
        Preferences.globalKey = key
        let controller = PreferencesWindowController(context: fullContext())
        let views = allViews(controller)
        let recorder = try XCTUnwrap(control(UserDefaults.Key.globalKey, in: views) as? NSButton)
        XCTAssertEqual(recorder.title, key.description)

        let general = try XCTUnwrap(controller.pane(.general) as? PreferencesViewController)
        general.unregister(nil)
        XCTAssertNil(UserDefaults.standard.object(forKey: UserDefaults.Key.globalKey).flatMap { $0 as? Data }
            .flatMap { try? JSONDecoder().decode(GlobalKeybindPreferences.self, from: $0) })
    }

    // Given the window built for each build
    // When looking for the controls that only one build has
    // Then the App Store build has no macOS 27 rows, no updater and no Check for Updates
    func test_appStoreBuild_hidesDirectOnlyRows() {
        var context = fullContext()
        context.build = .appStore
        let views = allViews(PreferencesWindowController(context: context))
        for key in [UserDefaults.Key.pauseHidingForUnkeepableItems, UserDefaults.Key.showWholeBarWhenCaptureStarts,
                    UserDefaults.Key.pinnedSectionsEnabled, "SUEnableAutomaticChecks"] {
            XCTAssertNil(control(key, in: views), "\(key) shows in the App Store build")
        }
        XCTAssertNil(control(AboutViewController.checkForUpdatesIdentifier.rawValue, in: views))
        let texts = views.compactMap { ($0 as? NSTextField)?.stringValue } + views.compactMap { ($0 as? NSButton)?.title }
        XCTAssertFalse(texts.contains { $0.localizedCaseInsensitiveContains("Direct Version") }, "App Store build links the direct version")
        XCTAssertNotNil(control(AboutViewController.checkForUpdatesIdentifier.rawValue,
                                in: allViews(PreferencesWindowController(context: fullContext()))))
    }

    // MARK: tabs

    // Given the Menu Bar Apps slot empty, then filled
    // When the window builds its toolbar
    // Then the tab appears only once the slot is filled, in second place
    func test_menuBarAppsTab_appearsWhenRegistered() {
        XCTAssertEqual(PreferencesWindowController(context: fullContext()).tabs, [.general, .appearance, .advanced, .about])

        MenuBarAppsPane.makeViewController = { NSViewController(nibName: nil, bundle: nil) }
        var context = fullContext()
        context.menuBarAppsAvailable = MenuBarAppsPane.makeViewController != nil
        let controller = PreferencesWindowController(context: context)
        XCTAssertEqual(controller.tabs, [.general, .menuBarApps, .appearance, .advanced, .about])
        XCTAssertNil(controller.window?.toolbar, "a toolbar brings back the glass item platters")
        XCTAssertEqual((0..<controller.tabControl.segmentCount).map { controller.tabControl.label(forSegment: $0) },
                       controller.tabs.map { $0.titleKey.localized })
    }

    // Given the pinned sections beta with two known apps
    // When picking a section in an app's popup, then clicking Reset
    // Then the table under the pinnedSections key follows, and nothing else is written
    func test_menuBarApps_popupsAndResetWriteThePinnedTable() throws {
        UserDefaults.standard.set(true, forKey: UserDefaults.Key.pinnedSectionsEnabled)
        UserDefaults.standard.set(["com.test.a": MenuBarSection.hidden.rawValue, "com.test.b": MenuBarSection.visible.rawValue],
                                  forKey: UserDefaultsPinnedSections.key)
        var context = fullContext()
        MenuBarAppsPane.makeViewController = { MenuBarAppsSettingsViewController(context: context) }
        context.menuBarAppsAvailable = true
        let controller = PreferencesWindowController(context: context)
        windows.append(controller)
        let views = Self.subviews(of: controller.pane(.menuBarApps).view)

        let popup = try XCTUnwrap(control(MenuBarAppsSettingsViewController.popupIdentifier(for: "com.test.a"), in: views) as? NSPopUpButton)
        XCTAssertEqual(popup.selectedItem?.tag, MenuBarSection.hidden.rawValue)
        popup.selectItem(withTag: MenuBarSection.alwaysHidden.rawValue)
        popup.sendAction(popup.action, to: popup.target)
        XCTAssertEqual(UserDefaults.standard.dictionary(forKey: UserDefaultsPinnedSections.key) as? [String: Int],
                       ["com.test.a": MenuBarSection.alwaysHidden.rawValue, "com.test.b": MenuBarSection.visible.rawValue])

        let views2 = Self.subviews(of: controller.pane(.menuBarApps).view)
        let reset = try XCTUnwrap(views2.compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "pinnedSectionsReset" })
        reset.performClick(nil)
        XCTAssertEqual(UserDefaults.standard.dictionary(forKey: UserDefaultsPinnedSections.key) as? [String: Int],
                       ["com.test.a": 0, "com.test.b": 0])
    }

    // Given the beta off
    // When opening Menu Bar Apps
    // Then it says so and lists no app
    func test_menuBarApps_offShowsNoList() {
        UserDefaults.standard.set(false, forKey: UserDefaults.Key.pinnedSectionsEnabled)
        UserDefaults.standard.set(["com.test.a": MenuBarSection.hidden.rawValue], forKey: UserDefaultsPinnedSections.key)
        var context = fullContext()
        MenuBarAppsPane.makeViewController = { MenuBarAppsSettingsViewController(context: context) }
        context.menuBarAppsAvailable = true
        let controller = PreferencesWindowController(context: context)
        windows.append(controller)
        let views = Self.subviews(of: controller.pane(.menuBarApps).view)
        XCTAssertNil(control(MenuBarAppsSettingsViewController.popupIdentifier(for: "com.test.a"), in: views))
        XCTAssertTrue(views.contains { ($0 as? NSTextField)?.stringValue == "Pinned sections is off".localized })
    }

    // Given each tab
    // When selecting it
    // Then the tab control and the (hidden) window title follow, and General stays within 720 pt
    func test_selectingATab_titlesTheWindow() throws {
        let controller = PreferencesWindowController(context: fullContext())
        for tab in controller.tabs {
            controller.select(tab, animate: false)
            XCTAssertEqual(controller.window?.title, tab.titleKey.localized)
            XCTAssertTrue(controller.currentPane === controller.pane(tab))
            XCTAssertNotNil(controller.pane(tab).view.window, "\(tab) pane is not in the window")
            XCTAssertEqual(controller.tabControl.selectedSegment, controller.tabs.firstIndex(of: tab))
        }
        controller.select(.general, animate: false)
        let height = try XCTUnwrap(controller.window?.frame.height)
        XCTAssertLessThanOrEqual(height, 720)
    }

    // MARK: status card

    // Given each status
    // When General shows it
    // Then the card's title and single button match the state
    func test_statusCard_showsEachState() throws {
        let expected: [(SettingsStatus, String, String?)] = [
            (.working, "Hidden Bar is working", nil),
            (.needsAccessibility, "Hidden Bar needs Accessibility access", "Open System Settings"),
            (.outsideApplications, "Move Hidden Bar to Applications", "Move to Applications"),
            (.appStoreOnMacOS27, "This App Store version can't hide icons on macOS 27", "Learn More…"),
        ]
        for (status, title, button) in expected {
            let general = try XCTUnwrap(PreferencesWindowController(context: fullContext(status)).pane(.general) as? PreferencesViewController)
            _ = general.view
            XCTAssertEqual(general.statusCard.status, status)
            XCTAssertEqual(general.statusCard.title, title.localized)
            XCTAssertEqual(general.statusCard.buttonTitle, button?.localized)
        }
    }

    // Given the new window's strings
    // When looking in every Localizable.strings the app ships
    // Then each locale carries them (English text for now), so none shows a raw key
    func test_everyLocale_carriesTheSettingsKeys() {
        let keys = ["Hidden Bar is working", "Hide icons again", "Never", "After %d seconds", "Your menu bar",
                    "This App Store version can't hide icons on macOS 27", "Check for Updates…", "What's new"]
        let localizations = Bundle.main.localizations.filter { $0 != "Base" }
        XCTAssertGreaterThan(localizations.count, 5)
        for locale in localizations {
            guard let path = Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: locale),
                  let table = NSDictionary(contentsOfFile: path) as? [String: String] else {
                XCTFail("no Localizable.strings for \(locale)")
                continue
            }
            for key in keys {
                XCTAssertNotNil(table[key], "\(locale) is missing \"\(key)\"")
            }
        }
    }

    // Given the direct build on macOS 27, then the separator engine
    // When General draws the preview
    // Then the arrow is the edge on 27 and the "|" separator otherwise
    func test_preview_matchesTheEngine() throws {
        var context = fullContext()
        let native = try XCTUnwrap(PreferencesWindowController(context: context).pane(.general) as? PreferencesViewController)
        _ = native.view
        XCTAssertEqual(native.preview.boundary, .arrow)

        context.osMajorVersion = 26
        let legacy = try XCTUnwrap(PreferencesWindowController(context: context).pane(.general) as? PreferencesViewController)
        _ = legacy.view
        XCTAssertEqual(legacy.preview.boundary, .separator)
    }
}
