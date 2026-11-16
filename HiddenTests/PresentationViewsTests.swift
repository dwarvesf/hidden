//
//  PresentationViewsTests.swift
//  HiddenTests
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import XCTest
import AppKit
@testable import Hidden_Bar

/// Contract: presentation mode's Settings group, its sensitive-apps picker and
/// the panels the capsule opens say what the boards say, and write only what the
/// user chose.
/// Serves: PreferencesViewController (Presentation mode group), PresentationSensitiveApps,
/// PresentationViews.
/// Mock boundary: real `UserDefaults.standard` for the preference accessors (the
/// keys are saved in setUp and put back); the picker takes injected read and write.
final class PresentationViewsTests: XCTestCase {
    private let keys = [UserDefaults.Key.presentationAutoMirrorEnabled, UserDefaults.Key.presentationSensitiveApps,
                        UserDefaults.Key.presentationShortcut, UserDefaults.Key.presentationModeActive,
                        UserDefaults.Key.presentationTipShown]
    private var saved: [String: Any] = [:]
    private var windows: [PreferencesWindowController] = []

    override func setUp() {
        super.setUp()
        for key in keys { saved[key] = UserDefaults.standard.object(forKey: key) }
    }

    override func tearDown() {
        for key in keys {
            if let value = saved[key] { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }
        windows.removeAll()
        super.tearDown()
    }

    private func views(build: SettingsBuild = .direct, os: Int = 27) -> [NSView] {
        var context = SettingsContext.live
        context.build = build
        context.osMajorVersion = os
        context.statusOverride = .working
        let controller = PreferencesWindowController(context: context)
        windows.append(controller)
        return Self.subviews(of: controller.pane(.general).view)
    }

    private static func subviews(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap { subviews(of: $0) }
    }

    private func control(_ key: String, in views: [NSView]) -> NSControl? {
        views.compactMap { $0 as? NSControl }.first { $0.identifier?.rawValue == key }
    }

    private func texts(_ views: [NSView]) -> [String] {
        views.compactMap { ($0 as? NSTextField)?.stringValue }
    }

    // MARK: Settings group

    // Given the direct build on macOS 27
    // When General draws
    // Then the Presentation mode group has its trigger, sensitive apps, shortcut and the camera footnote
    func test_group_hasItsRowsAndFootnote() {
        let all = views()
        XCTAssertTrue(texts(all).contains("Presentation mode".localized))
        XCTAssertNotNil(control(UserDefaults.Key.presentationAutoMirrorEnabled, in: all))
        XCTAssertNotNil(control(UserDefaults.Key.presentationSensitiveApps, in: all), "the Edit button carries the key")
        XCTAssertNotNil(control(UserDefaults.Key.presentationShortcut, in: all), "the recorder button carries the key")
        XCTAssertTrue(texts(all).contains("How it works"), "the how-it-works block heads the group's footnote")
        XCTAssertTrue(texts(all).contains("Stay hidden while presenting, even when you click the arrow, except while hiding is paused for the camera or microphone."),
                      "the Sensitive apps caption carries the same exception")
    }

    // Given the direct build on macOS 27
    // When General draws
    // Then the group says how presentation mode works: how to start it, what stays, the
    // camera or microphone pause with its switch, and how to stop, each fact once
    func test_group_saysHowItWorks() throws {
        let all = texts(views())
        let lines = PreferencesViewController.howItWorksLines
        for line in lines { XCTAssertTrue(all.contains(line), "missing: \(line)") }
        let start = try XCTUnwrap(lines.first { $0.hasPrefix("Start it with") })
        XCTAssertTrue(start.contains("shortcut") && start.contains("right-click menu") && start.contains("display is mirrored"))
        let camera = try XCTUnwrap(lines.first { $0.contains("microphone or camera turns on") })
        XCTAssertTrue(camera.contains("pauses hiding once") && camera.contains("With the switch off, hiding never pauses"))
        XCTAssertTrue(camera.contains("already on when you start does not pause"))
        let stop = try XCTUnwrap(lines.first { $0.hasPrefix("Stop it from") })
        XCTAssertTrue(stop.contains("capsule") && stop.contains("shortcut") && stop.contains("right-click menu") && stop.contains("mirroring stops"))
        XCTAssertEqual(Set(lines).count, lines.count, "no sentence repeats")
        let caption = "Stay hidden while presenting, even when you click the arrow, except while hiding is paused for the camera or microphone."
        XCTAssertTrue(all.contains(caption))
        XCTAssertFalse(lines.contains { $0.contains("even when you click the arrow") }, "the Sensitive apps caption says that once")
        XCTAssertFalse(all.contains { $0.hasPrefix("Sensitive apps stay hidden while presenting, except when") }, "the old footnote is folded in")
        for text in lines + ["How it works"] {
            XCTAssertFalse(text.contains("\u{2014}") || text.contains("\u{2013}"), "no em or en dashes")
        }
    }

    // Given a build or macOS without native hiding
    // When General draws
    // Then there is no Presentation mode group
    func test_group_isDirectMacOS27Only() {
        for (build, os) in [(SettingsBuild.appStore, 27), (.direct, 26)] {
            let all = views(build: build, os: os)
            XCTAssertFalse(texts(all).contains("Presentation mode".localized), "\(build) \(os)")
            XCTAssertNil(control(UserDefaults.Key.presentationAutoMirrorEnabled, in: all))
        }
    }

    // MARK: Preferences

    // Given the sensitive set
    // When writing and reading it
    // Then it is stored as a dictionary [bundle id: true] under the contract key
    func test_sensitiveApps_areStoredAsADictionary() {
        Preferences.presentationSensitiveApps = ["com.a", "com.b"]
        let stored = UserDefaults.standard.dictionary(forKey: UserDefaults.Key.presentationSensitiveApps)
        XCTAssertEqual(stored as? [String: Bool], ["com.a": true, "com.b": true])
        XCTAssertEqual(Preferences.presentationSensitiveApps, ["com.a", "com.b"])
        UserDefaults.standard.set(["com.a": true, "com.c": false], forKey: UserDefaults.Key.presentationSensitiveApps)
        XCTAssertEqual(Preferences.presentationSensitiveApps, ["com.a"], "a false entry is not sensitive")
    }

    // MARK: Picker

    // Given two cataloged apps and one chosen app the catalog no longer sees
    // When ticking and unticking
    // Then the stored set follows, including the unseen one
    func test_picker_togglesTheStoredSet() throws {
        var chosen: Set<String> = ["com.gone"]
        let icon = NSImage(size: NSSize(width: 16, height: 16))
        let entries = [MenuBarCatalogEntry(bundleIdentifier: "com.a", name: "Alpha", icon: icon, section: .hidden, firstSeen: Date(), isRunning: true),
                       MenuBarCatalogEntry(bundleIdentifier: "com.b", name: "Beta", icon: icon, section: .visible, firstSeen: Date(), isRunning: true)]
        let editor = PresentationSensitiveAppsEditor(entries: entries, read: { chosen }, write: { chosen = $0 })
        _ = editor.view
        XCTAssertEqual(editor.checkboxes.count, 3)
        let alpha = try XCTUnwrap(editor.checkboxes.first { $0.identifier == PresentationSensitiveAppsEditor.checkboxIdentifier(for: "com.a") })
        let gone = try XCTUnwrap(editor.checkboxes.first { $0.identifier == PresentationSensitiveAppsEditor.checkboxIdentifier(for: "com.gone") })
        XCTAssertEqual(gone.state, .on)

        alpha.state = .on
        alpha.sendAction(alpha.action, to: alpha.target)
        XCTAssertEqual(chosen, ["com.a", "com.gone"])
        gone.state = .off
        gone.sendAction(gone.action, to: gone.target)
        XCTAssertEqual(chosen, ["com.a"])
    }

    // MARK: Panels

    private func panel(_ kind: PresentationPanelModel.Kind, cause: PresentationCause? = .manual,
                       hidden: Int = 3, stays: Int = 1) -> PresentationPanelView {
        return PresentationPanelView(model: PresentationPanelModel(kind: kind, cause: cause, hiddenCount: hidden, sensitiveCount: stays))
    }

    // Given the presenting panel
    // When pressing Stop Presenting
    // Then it asks the controller to stop
    func test_panel_stopButtonStops() throws {
        let view = panel(.presenting)
        var stopped = 0
        view.onStop = { stopped += 1 }
        let stop = try XCTUnwrap(Self.subviews(of: view).compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "presentationStop" })
        stop.performClick(nil)
        XCTAssertEqual(stopped, 1)
        XCTAssertTrue(texts(Self.subviews(of: view)).contains("macOS's own items stay.".localized))
    }

    // Given each way presentation mode starts
    // When the panel says why
    // Then a mirror names its display and says when it ends; a manual start says it stays
    func test_panel_saysWhyItStarted() {
        XCTAssertEqual(PresentationPanelView.causeText(.mirroring(displayName: "Meeting Room TV")),
                       "Started because \"Meeting Room TV\" is mirrored. Ends when mirroring stops.")
        XCTAssertTrue(PresentationPanelView.causeText(.mirroring(displayName: nil)).contains("a display is mirrored"))
        XCTAssertTrue(PresentationPanelView.causeText(.manual).contains("until you stop it"))
    }

    // Given the pause panel
    // When read
    // Then it says nothing is hidden (sensitive apps included), names the capsule macOS hides,
    // never claims the corner dot is hidden, and "Hide again" resumes hiding
    func test_pausedPanel_isHonestAboutTheCapsule() throws {
        let view = panel(.paused)
        let all = texts(Self.subviews(of: view))
        let body = try XCTUnwrap(all.first { $0.hasPrefix("Nothing is hidden right now") })
        XCTAssertTrue(body.contains("sensitive apps included"))
        XCTAssertTrue(body.contains("capsule that names the app"))
        XCTAssertFalse(all.contains { $0.localizedCaseInsensitiveContains("privacy light") || $0.localizedCaseInsensitiveContains("camera light") })
        XCTAssertTrue(all.contains("Share one window, not the whole screen".localized))
        XCTAssertTrue(all.contains("Resumes on its own.".localized))
        var hideAgain = 0
        view.onHideAgain = { hideAgain += 1 }
        let button = try XCTUnwrap(Self.subviews(of: view).compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "presentationHideAgain" })
        XCTAssertEqual(button.title, "Hide again")
        button.performClick(nil)
        XCTAssertEqual(hideAgain, 1)
    }

    // Given hidden and sensitive apps
    // When the presenting panel draws on the shared screen
    // Then it gives exact counts and names no app: no chips, no list
    func test_panel_countsAppsAndNamesNone() {
        let view = panel(.presenting, hidden: 11, stays: 3)
        let all = texts(Self.subviews(of: view))
        XCTAssertTrue(all.contains("Hidden now: 11 apps"))
        XCTAssertTrue(all.contains("3 sensitive apps stay hidden even if you click the arrow"))
        XCTAssertFalse(Self.subviews(of: view).contains { $0 is PresentationChipFlow }, "no app chips on the shared screen")
        XCTAssertFalse(all.contains { $0.contains("App ") || $0.contains("more") }, "no names, no +N more")

        let one = texts(Self.subviews(of: panel(.presenting, hidden: 1, stays: 1)))
        XCTAssertTrue(one.contains("Hidden now: 1 app"))
        XCTAssertTrue(one.contains("1 sensitive app stays hidden even if you click the arrow"))
        let none = texts(Self.subviews(of: panel(.presenting, hidden: 1, stays: 0)))
        XCTAssertFalse(none.contains { $0.contains("sensitive") }, "no lock row without sensitive apps")
    }

    // MARK: Note, capsule, menu

    // Given sensitive apps while presenting
    // When the arrow note draws on the shared screen
    // Then it gives a count and never a name
    func test_note_countsAppsAndNamesNone() {
        XCTAssertEqual(PresentationNoteView.text(count: 1), "1 app stays hidden")
        XCTAssertEqual(PresentationNoteView.text(count: 2), "2 apps stay hidden")
        XCTAssertEqual(PresentationNoteView.text(count: 12), "12 apps stay hidden")
        let view = PresentationNoteView(count: 3)
        XCTAssertEqual(texts(Self.subviews(of: view)), ["3 apps stay hidden"])
    }

    func test_capsule_readsEachPhase() {
        XCTAssertEqual(PresentationCapsule.title(for: .presenting), "Presenting")
        XCTAssertEqual(PresentationCapsule.title(for: .paused), "Paused")
        XCTAssertEqual(PresentationCapsule.title(for: .couldNotHide), "Couldn't hide")
        for phase in [PresentationPhase.presenting, .paused, .couldNotHide] {
            XCTAssertEqual(PresentationCapsule.image(for: phase).size.height, PresentationCapsule.height)
        }
        XCTAssertGreaterThan(PresentationCapsule.image(for: .presenting).size.width, PresentationCapsule.image(for: .paused).size.width,
                             "the presenting capsule carries an icon")
    }

    // Given the stored shortcut ⌥⌘P
    // When the arrow menu item shows it
    // Then the item carries the key and modifiers the board draws
    func test_menuItem_showsTheShortcut() {
        let shortcut = GlobalKeybindPreferences(function: false, control: false, command: true, shift: false, option: true,
                                                capsLock: false, carbonFlags: 0, characters: "p", keyCode: 35)
        let item = NSMenuItem(title: "Start Presentation Mode", action: nil, keyEquivalent: "")
        item.setShortcut(shortcut)
        XCTAssertEqual(item.keyEquivalent, "p")
        XCTAssertEqual(item.keyEquivalentModifierMask, [.command, .option])
        let plain = NSMenuItem(title: "x", action: nil, keyEquivalent: "")
        plain.setShortcut(nil)
        XCTAssertEqual(plain.keyEquivalent, "")
    }

    // MARK: First-start tip

    private func suite(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    // Given a first start that reaches hiding
    // When the tip is asked for, shown, and a later start (in a new launch) asks again
    // Then it shows exactly once, because the flag lives in the preferences
    func test_tip_showsExactlyOnceAcrossLaunches() {
        let first = suite("PresentationTipLaunch")
        XCTAssertTrue(PresentationTip.shouldShow(previous: .off, phase: .presenting, panelShown: false, defaults: first))
        PresentationTip.markShown(defaults: first)
        XCTAssertFalse(PresentationTip.shouldShow(previous: .off, phase: .presenting, panelShown: false, defaults: first))
        // A relaunch is a new defaults object over the same stored domain.
        let relaunched = UserDefaults(suiteName: "PresentationTipLaunch")!
        XCTAssertFalse(PresentationTip.shouldShow(previous: .off, phase: .presenting, panelShown: false, defaults: relaunched),
                       "a later start does not show it again")
    }

    // Given the standard preferences
    // When the flag is written and read back
    // Then it is the internal key: false until the tip is shown, and not imported from the App Store build
    func test_tip_flagIsAnInternalPreference() {
        UserDefaults.standard.removeObject(forKey: UserDefaults.Key.presentationTipShown)
        XCTAssertFalse(Preferences.presentationTipShown)
        PresentationTip.markShown()
        XCTAssertTrue(Preferences.presentationTipShown)
        XCTAssertEqual(UserDefaults.Key.presentationTipShown, "presentationTipShown")
        XCTAssertNil(AppStoreSettingsImport.importableKeys[UserDefaults.Key.presentationTipShown])
    }

    // Given the other moments the phase changes
    // When asking for the tip
    // Then it stays quiet: a resume, a pause, a failure, or a panel already open under the capsule
    func test_tip_staysQuietWhenItWouldNotHelp() {
        let defaults = suite("PresentationTipQuiet")
        XCTAssertFalse(PresentationTip.shouldShow(previous: .paused, phase: .presenting, panelShown: false, defaults: defaults), "a resume")
        XCTAssertFalse(PresentationTip.shouldShow(previous: .off, phase: .paused, panelShown: false, defaults: defaults))
        XCTAssertFalse(PresentationTip.shouldShow(previous: .off, phase: .couldNotHide, panelShown: false, defaults: defaults),
                       "nothing is hidden, so the tip would be untrue")
        XCTAssertFalse(PresentationTip.shouldShow(previous: .off, phase: .off, panelShown: false, defaults: defaults))
        XCTAssertFalse(PresentationTip.shouldShow(previous: .off, phase: .presenting, panelShown: true, defaults: defaults),
                       "never over the capsule's own panel")
        XCTAssertFalse(defaults.bool(forKey: UserDefaults.Key.presentationTipShown), "asking does not use up the one showing")
    }

    // Given sensitive apps chosen and the tip drawn on the shared screen
    // When read
    // Then it is three short lines, a heading and Got it, and names no app
    func test_tip_isThreeLinesAndNamesNoApp() throws {
        Preferences.presentationSensitiveApps = ["com.tinyspeck.slackmacgap"]
        for pauses in [true, false] {
            let view = PresentationTipView(pausesForCapture: pauses)
            let all = texts(Self.subviews(of: view))
            XCTAssertEqual(PresentationTip.lines(pausesForCapture: pauses).count, 3)
            for line in PresentationTip.lines(pausesForCapture: pauses) { XCTAssertTrue(all.contains(line)) }
            XCTAssertTrue(all.contains("Presentation mode is on"))
            XCTAssertFalse(all.contains { $0.contains("Slack") || $0.contains("1Password") || $0.contains("slack") || $0.contains("com.") },
                           "no app name on a shared screen")
            XCTAssertFalse(Self.subviews(of: view).contains { $0 is PresentationChipFlow || $0 is PresentationChipView })
            XCTAssertFalse(all.contains { $0.contains("\u{2014}") || $0.contains("\u{2013}") })
        }
        let on = PresentationTip.lines(pausesForCapture: true)[2]
        let off = PresentationTip.lines(pausesForCapture: false)[2]
        XCTAssertTrue(on.contains("pauses once"), on)
        XCTAssertTrue(off.contains("keeps going"), "with the switch off the tip does not promise a pause: \(off)")
        let view = PresentationTipView(pausesForCapture: true)
        var dismissed = 0
        view.onGotIt = { dismissed += 1 }
        let button = try XCTUnwrap(Self.subviews(of: view).compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "presentationTipGotIt" })
        XCTAssertEqual(button.title, "Got it")
        button.performClick(nil)
        XCTAssertEqual(dismissed, 1)
    }

    // MARK: Menu item

    // Given the right-click menu
    // When presentation mode is off and then on
    // Then the item says what a click does
    func test_menuTitle_flipsWithTheMode() {
        XCTAssertEqual(PresentationController.menuTitle(isOn: false), "Start Presentation Mode")
        XCTAssertEqual(PresentationController.menuTitle(isOn: true), "Stop Presentation Mode")
    }
}
