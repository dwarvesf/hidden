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
                        UserDefaults.Key.presentationShortcut, UserDefaults.Key.presentationModeActive]
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
        let footnote = texts(all).first { $0.hasPrefix("Sensitive apps stay hidden while presenting, except when \"Show all icons when the microphone or camera turns on\" pauses hiding") }
        XCTAssertNotNil(footnote)
        XCTAssertTrue(footnote?.contains("nothing is hidden") ?? false, "a pause lifts everything, sensitive apps too")
        XCTAssertFalse(footnote?.localizedCaseInsensitiveContains("light") ?? true,
                       "macOS hides the capsule that names the app, not the dot in the corner")
        XCTAssertTrue(texts(all).contains("Stay hidden while presenting, even when you click the arrow, except while hiding is paused for the camera or microphone."),
                      "the Sensitive apps caption carries the same exception")
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
}
