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
        UserDefaults.Key.revealOnScrollEnabled,            // Scroll down on the menu bar
        UserDefaults.Key.revealOnEmptyClickEnabled,        // Click empty space in the menu bar, direct only
        UserDefaults.Key.revealOnShakeEnabled,             // Shake the pointer at the top of the screen
        UserDefaults.Key.notchOverflowEnabled,             // Enable Notch Overflow (notch Macs)
        UserDefaults.Key.pauseHidingForUnkeepableItems,    // macOS 27 direct only
        UserDefaults.Key.showWholeBarWhenCaptureStarts,    // macOS 27 direct only
        UserDefaults.Key.pinnedSectionsEnabled,            // Pinned sections (beta), macOS 27 direct only
        UserDefaults.Key.presentationAutoMirrorEnabled,    // Presentation mode: turn on while a display is mirrored, macOS 27 direct only
        "SUEnableAutomaticChecks",                         // Sparkle, direct only
    ]
    static let legacyOtherKeys = [
        UserDefaults.Key.isAutoHide, UserDefaults.Key.numberOfSecondForAutoHide, // checkbox + delay popup
        UserDefaults.Key.arrowStyle,                                              // arrow style popup
        UserDefaults.Key.globalKey,                                               // global shortcut
        UserDefaults.Key.findHiddenIconShortcut,                                  // Find a hidden icon shortcut, direct on macOS 27
        UserDefaultsPinnedSections.key,                                           // Icons section popups (beta)
        UserDefaults.Key.newAppDefaultSection,                                    // Icons: when an app adds a new icon
        UserDefaults.Key.presentationShortcut,                                    // Presentation mode shortcut, macOS 27 direct only
        UserDefaults.Key.presentationSensitiveApps,                               // Presentation mode sensitive apps, macOS 27 direct only
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
        // The notch switch does not exist on macOS 27; its own test covers it.
        for key in Self.legacyBoolKeys where key != UserDefaults.Key.notchOverflowEnabled {
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

    // Given a notch Mac on macOS 26, then on macOS 27
    // When building the Advanced pane
    // Then the notch switch writes its old key on 26 and is absent on 27
    func test_notchSwitch_existsOnlyBeforeMacOS27() {
        var context = fullContext()
        context.build = .appStore
        context.osMajorVersion = 26
        let old = allViews(PreferencesWindowController(context: context))
        let toggle = control(UserDefaults.Key.notchOverflowEnabled, in: old)
        XCTAssertNotNil(toggle, "macOS 26 keeps the notch switch")
        if let toggle {
            let before = UserDefaults.standard.bool(forKey: UserDefaults.Key.notchOverflowEnabled)
            click(toggle)
            XCTAssertEqual(UserDefaults.standard.bool(forKey: UserDefaults.Key.notchOverflowEnabled), !before)
        }

        context.osMajorVersion = 27
        XCTAssertNil(control(UserDefaults.Key.notchOverflowEnabled, in: allViews(PreferencesWindowController(context: context))),
                     "macOS 27 never hides icons behind the notch, so no switch")
    }

    // Given the OS major version and whether the screen has a notch
    // When asking whether notch overflow applies
    // Then it does only on a notch before macOS 27
    func test_notchOverflowSupport_gate() {
        XCTAssertTrue(NotchOverflowSupport.isAvailable(osMajorVersion: 26, hasNotch: true))
        XCTAssertTrue(NotchOverflowSupport.isAvailable(osMajorVersion: 14, hasNotch: true))
        XCTAssertFalse(NotchOverflowSupport.isAvailable(osMajorVersion: 26, hasNotch: false))
        XCTAssertFalse(NotchOverflowSupport.isAvailable(osMajorVersion: 27, hasNotch: true))
        XCTAssertFalse(NotchOverflowSupport.isAvailable(osMajorVersion: 28, hasNotch: true))
        XCTAssertFalse(NotchOverflowSupport.isAvailable(osMajorVersion: 27, hasNotch: false))
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
        general.shortcutRecorder.clear()
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
                    UserDefaults.Key.pinnedSectionsEnabled, UserDefaults.Key.revealOnEmptyClickEnabled,
                    UserDefaults.Key.newAppDefaultSection, UserDefaults.Key.findHiddenIconShortcut,
                    UserDefaults.Key.presentationAutoMirrorEnabled, UserDefaults.Key.presentationShortcut,
                    UserDefaults.Key.presentationSensitiveApps, "SUEnableAutomaticChecks"] {
            XCTAssertNil(control(key, in: views), "\(key) shows in the App Store build")
        }
        // Scroll and shake need no Accessibility, so the App Store build keeps them.
        XCTAssertNotNil(control(UserDefaults.Key.revealOnScrollEnabled, in: views))
        XCTAssertNotNil(control(UserDefaults.Key.revealOnShakeEnabled, in: views))
        XCTAssertNil(control(AboutViewController.checkForUpdatesIdentifier.rawValue, in: views))
        let texts = views.compactMap { ($0 as? NSTextField)?.stringValue } + views.compactMap { ($0 as? NSButton)?.title }
        XCTAssertFalse(texts.contains { $0.localizedCaseInsensitiveContains("Direct Version") }, "App Store build links the direct version")
        XCTAssertNotNil(control(AboutViewController.checkForUpdatesIdentifier.rawValue,
                                in: allViews(PreferencesWindowController(context: fullContext()))))
    }

    // MARK: tabs

    // Given the Icons slot empty, then filled
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

    // Given a running app, one that is not, and the macOS extras row (never an app)
    // When the Icons pane builds
    // Then only the app that is not running says so and offers Remove; Remove goes to the store
    func test_menuBarApps_removeIsOfferedOnlyForAppsNotRunning() throws {
        let store = FakeAppsStore(bundles: ["com.test.run", "com.test.gone", MenuBarLayoutResolver.systemExtrasBundle], running: ["com.test.run"])
        let pane = MenuBarAppsSettingsViewController(context: fullContext(), store: store)
        let views = Self.subviews(of: pane.view)
        func remove(_ bundle: String) -> NSControl? {
            control(MenuBarAppsSettingsViewController.removeIdentifier(for: bundle), in: views)
        }
        XCTAssertNil(remove("com.test.run"))
        XCTAssertNil(remove(MenuBarLayoutResolver.systemExtrasBundle))
        let button = try XCTUnwrap(remove("com.test.gone") as? NSButton)
        XCTAssertEqual(button.title, "Remove".localized)
        XCTAssertEqual(button.accessibilityLabel(), "Remove".localized + " com.test.gone")
        XCTAssertFalse(button.isBordered, "a link in the caption line, so the controls column is the same on every row")
        XCTAssertEqual(views.compactMap { ($0 as? NSTextField)?.stringValue }.filter { $0.hasPrefix("Not running".localized) }.count, 1)
        pane.view.layoutSubtreeIfNeeded()
        let sectionPopups = views.compactMap { $0 as? NSPopUpButton }.filter { $0.identifier?.rawValue != UserDefaults.Key.newAppDefaultSection }
        let edges = Set(sectionPopups.map { $0.superview?.frame.minX ?? 0 })
        XCTAssertEqual(edges.count, 1, "the controls column starts at the same x on every row")
        XCTAssertGreaterThan(edges.first ?? 0, 0, "the pane was laid out")
        XCTAssertEqual(store.runningReads, 1, "the running set is read once per rebuild, not per row")

        button.performClick(nil)
        XCTAssertEqual(store.removed, ["com.test.gone"])
    }

    // Given a pane built while an app runs
    // When the app quits and the pane appears again, then appears again with nothing changed
    // Then the first appearance gives the row its Remove button and the second keeps the same rows
    func test_menuBarApps_aQuitAppUpdatesItsRowOnTheNextAppearance() throws {
        let store = FakeAppsStore(bundles: ["com.test.a", "com.test.b"], running: ["com.test.a", "com.test.b"])
        let pane = MenuBarAppsSettingsViewController(context: fullContext(), store: store)
        let removeA = MenuBarAppsSettingsViewController.removeIdentifier(for: "com.test.a")
        XCTAssertNil(control(removeA, in: Self.subviews(of: pane.view)))

        store.running = ["com.test.b"]
        pane.viewWillAppear()
        let button = try XCTUnwrap(control(removeA, in: Self.subviews(of: pane.view)))

        pane.viewWillAppear()
        XCTAssertTrue(control(removeA, in: Self.subviews(of: pane.view)) === button, "nothing changed: the rows are not rebuilt")
        XCTAssertEqual(store.runningReads, 3, "one read per appearance")
    }

    // Given the Icons pane
    // When picking Ask Me, then Hide It, then Show It in "When an app adds a new icon"
    // Then newAppDefaultSection holds 0, 2, 1, and the popup starts on Show It when nothing is stored
    func test_menuBarApps_newAppPopupWritesItsKey() throws {
        UserDefaults.standard.set(true, forKey: UserDefaults.Key.pinnedSectionsEnabled)
        UserDefaults.standard.removeObject(forKey: UserDefaults.Key.newAppDefaultSection)
        var context = fullContext()
        MenuBarAppsPane.makeViewController = { MenuBarAppsSettingsViewController(context: context) }
        context.menuBarAppsAvailable = true
        let controller = PreferencesWindowController(context: context)
        windows.append(controller)
        let views = Self.subviews(of: controller.pane(.menuBarApps).view)
        let popup = try XCTUnwrap(control(UserDefaults.Key.newAppDefaultSection, in: views) as? NSPopUpButton)

        XCTAssertEqual(popup.selectedItem?.tag, NewAppDefault.show.rawValue)
        XCTAssertEqual(popup.itemTitles, ["Ask Me", "Show It", "Hide It"])
        for choice in [NewAppDefault.ask, .hide, .show] {
            popup.selectItem(withTag: choice.rawValue)
            popup.sendAction(popup.action, to: popup.target)
            XCTAssertEqual(UserDefaults.standard.integer(forKey: UserDefaults.Key.newAppDefaultSection), choice.rawValue)
            XCTAssertEqual(Preferences.newAppDefaultSection, choice)
        }
    }

    // Given the Icons pane
    // When picking each option in the new-app popup
    // Then the caption under the title describes that option
    func test_menuBarApps_newAppCaptionFollowsTheSelectedOption() throws {
        UserDefaults.standard.set(true, forKey: UserDefaults.Key.pinnedSectionsEnabled)
        UserDefaults.standard.removeObject(forKey: UserDefaults.Key.newAppDefaultSection)
        let pane = MenuBarAppsSettingsViewController(context: fullContext())
        let views = Self.subviews(of: pane.view)
        let popup = try XCTUnwrap(control(UserDefaults.Key.newAppDefaultSection, in: views) as? NSPopUpButton)
        func captions() -> [String] { Self.subviews(of: pane.view).compactMap { ($0 as? NSTextField)?.stringValue } }

        XCTAssertTrue(captions().contains(MenuBarAppsSettingsViewController.newAppCaption(for: .show)))
        for choice in [NewAppDefault.ask, .hide, .show] {
            popup.selectItem(withTag: choice.rawValue)
            popup.sendAction(popup.action, to: popup.target)
            let shown = captions()
            XCTAssertTrue(shown.contains(MenuBarAppsSettingsViewController.newAppCaption(for: choice)), "\(choice) caption missing")
            for other in [NewAppDefault.ask, .show, .hide] where other != choice {
                XCTAssertFalse(shown.contains(MenuBarAppsSettingsViewController.newAppCaption(for: other)), "\(other) caption still shown")
            }
        }
        XCTAssertEqual(Set([NewAppDefault.ask, .show, .hide].map(MenuBarAppsSettingsViewController.newAppCaption)).count, 3)
    }

    // Given a stored value outside 0 to 2, or none
    // Then the preference reads as Show It, the 1.12 behavior
    func test_newAppDefaultReadsShowItUnlessSet() {
        UserDefaults.standard.removeObject(forKey: UserDefaults.Key.newAppDefaultSection)
        XCTAssertEqual(Preferences.newAppDefaultSection, .show)
        UserDefaults.standard.set(9, forKey: UserDefaults.Key.newAppDefaultSection)
        XCTAssertEqual(Preferences.newAppDefaultSection, .show)
        UserDefaults.standard.set(0, forKey: UserDefaults.Key.newAppDefaultSection)
        XCTAssertEqual(Preferences.newAppDefaultSection, .ask)
    }

    // Given the beta off
    // Then the new-app popup is there but cannot be changed (nothing places a new app)
    func test_menuBarApps_newAppPopupIsDisabledWithPinnedSectionsOff() throws {
        UserDefaults.standard.set(false, forKey: UserDefaults.Key.pinnedSectionsEnabled)
        var context = fullContext()
        MenuBarAppsPane.makeViewController = { MenuBarAppsSettingsViewController(context: context) }
        context.menuBarAppsAvailable = true
        let controller = PreferencesWindowController(context: context)
        windows.append(controller)
        let popup = try XCTUnwrap(control(UserDefaults.Key.newAppDefaultSection,
                                          in: Self.subviews(of: controller.pane(.menuBarApps).view)) as? NSPopUpButton)

        XCTAssertFalse(popup.isEnabled)
    }

    // Given two apps waiting for an answer and two that are settled
    // When the Icons pane builds
    // Then the waiting ones come first, each with a NEW tag, and the settled ones have none
    func test_menuBarApps_undecidedAppsSitFirstWithANewTag() {
        let waitingKey = UserDefaultsArrivalsPending.key
        let before = UserDefaults.standard.object(forKey: waitingKey)
        addTeardownBlock {
            if let before { UserDefaults.standard.set(before, forKey: waitingKey) } else { UserDefaults.standard.removeObject(forKey: waitingKey) }
        }
        UserDefaults.standard.set(true, forKey: UserDefaults.Key.pinnedSectionsEnabled)
        UserDefaults.standard.set(["com.test.a": 0, "com.test.b": 1, "com.test.z": 0, "com.test.y": 0], forKey: UserDefaultsPinnedSections.key)
        UserDefaults.standard.set(["com.test.z", "com.test.y"], forKey: waitingKey)
        let pane = MenuBarAppsSettingsViewController(context: fullContext())
        let views = Self.subviews(of: pane.view)

        XCTAssertEqual(views.filter { $0 is NewTag }.count, 2)
        let prefix = UserDefaultsPinnedSections.key + "."
        let order = views.compactMap { ($0 as? NSPopUpButton)?.identifier?.rawValue }
            .filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
        XCTAssertEqual(order, ["com.test.y", "com.test.z", "com.test.a", "com.test.b"])
        XCTAssertTrue(views.contains { ($0 as? NSTextField)?.stringValue.hasPrefix("Not chosen yet".localized) == true })
        XCTAssertEqual(UserDefaults.Key.arrivalsPending, waitingKey)
    }

    // Given the beta off
    // When opening Icons
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
    // Then the tab control and the (hidden) window title follow, and General stays within the window cap
    // (720 pt) by scrolling: the fullest window, macOS 27 on the direct build, is taller than that
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
        XCTAssertLessThanOrEqual(height, PreferencesWindowController.maxWindowHeight)
        XCTAssertNotNil(controller.paneScroll.documentView, "General is taller than the cap, so it scrolls")
        XCTAssertTrue(controller.currentPane.view.isDescendant(of: controller.paneScroll))
        // A pane that fits is not wrapped in the scroll view.
        controller.select(.about, animate: false)
        XCTAssertNil(controller.paneScroll.documentView)
        XCTAssertNil(controller.paneScroll.superview)
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

/// A store with fixed apps and a running set the test can change.
private final class FakeAppsStore: MenuBarAppsStore {
    let bundles: [String]
    var running: Set<String>
    private(set) var runningReads = 0
    private(set) var removed: [String] = []

    init(bundles: [String], running: Set<String>) {
        self.bundles = bundles
        self.running = running
    }

    var isEnabled: Bool { true }
    func entries() -> [PinnedSectionsList.Entry] {
        PinnedSectionsList.entries(table: Dictionary(uniqueKeysWithValues: bundles.map { ($0, MenuBarSection.visible) }), name: { $0 })
    }
    func identity(for bundle: String) -> MenuBarAppIdentity.Resolved { .init(name: bundle, icon: .generic, caption: nil) }
    func icon(for bundle: String) -> NSImage { NSImage() }
    func runningBundles() -> Set<String> { runningReads += 1; return running }
    func set(_ section: MenuBarSection, for bundle: String) {}
    func setIgnoresDrags(_ ignores: Bool, for bundle: String) {}
    func resetAllToVisible() {}
    func remove(_ bundle: String) { removed.append(bundle) }
    func enable() {}
}
