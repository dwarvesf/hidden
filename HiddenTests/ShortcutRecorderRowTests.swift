//
//  ShortcutRecorderRowTests.swift
//  HiddenTests
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import XCTest
import AppKit
@testable import Hidden_Bar

/// Contract: the shortcut recorder reads and writes one `Data` preference key,
/// records the next combination, refuses a bare letter, can be cancelled or
/// cleared, warns when another Hidden Bar shortcut uses the same combination,
/// and makes the shortcut go live through the registry.
/// Mock boundary: a throwaway UserDefaults suite, a registry with a fake
/// binder instead of Carbon hot keys, and hand-made key events. No real key input.
final class ShortcutRecorderRowTests: XCTestCase {

    private final class FakeBinding {}

    private let key = "findHiddenIconShortcut"
    private let otherKey = "globalKey"
    private var suite: String!
    private var defaults: UserDefaults!
    private var bound: [GlobalKeybindPreferences] = []
    private var registry: HotKeyRegistry!
    private var row: ShortcutRecorderRow!

    override func setUp() {
        super.setUp()
        suite = "ShortcutRecorderRowTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        bound = []
        registry = HotKeyRegistry(defaults: defaults) { [unowned self] combo, _ in
            self.bound.append(combo)
            return FakeBinding()
        }
        registry.register(key: otherKey, title: "Show or hide icons") {}
        registry.register(key: key, title: "Find a hidden icon") {}
        row = ShortcutRecorderRow(key: key, registry: registry, defaults: defaults)
    }

    override func tearDown() {
        row.cancelRecording()
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func keyDown(_ characters: String, code: UInt16, flags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                         characters: characters, charactersIgnoringModifiers: characters.lowercased(), isARepeat: false, keyCode: code)!
    }

    private func flagsChanged(code: UInt16, flags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                         characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
    }

    private func store(_ combo: GlobalKeybindPreferences, for key: String) {
        defaults.set(try? JSONEncoder().encode(combo), forKey: key)
    }

    private func combo(_ code: UInt32, _ characters: String, flags: UInt32 = 0x108) -> GlobalKeybindPreferences {
        GlobalKeybindPreferences(function: false, control: false, command: true, shift: true, option: false, capsLock: false,
                                 carbonFlags: flags, characters: characters, keyCode: code)
    }

    private var stored: GlobalKeybindPreferences? { registry.shortcut(for: key) }

    // Given no stored shortcut, then the button invites one and there is nothing to clear
    func test_emptyRecorderShowsSetShortcut() {
        XCTAssertEqual(row.button.title, "Set Shortcut".localized)
        XCTAssertTrue(row.clearButton.isHidden)
        XCTAssertTrue(row.clashIcon.isHidden)
        XCTAssertEqual(row.button.identifier?.rawValue, key)
    }

    // Given a stored shortcut, then the button shows it and refresh follows a change from elsewhere
    func test_recorderShowsAndFollowsTheStoredShortcut() {
        store(combo(40, "k"), for: key)
        row.refresh()
        XCTAssertEqual(row.button.title, combo(40, "k").description)
        XCTAssertFalse(row.clearButton.isHidden)
        defaults.removeObject(forKey: key)
        row.refresh()
        XCTAssertEqual(row.button.title, "Set Shortcut".localized)
    }

    // Given the button pressed, when a combination is typed
    // Then it is stored under the key, the recorder stops listening, and the shortcut goes live
    func test_typedCombinationIsStoredAndGoesLive() throws {
        row.button.performClick(nil)
        XCTAssertTrue(row.isListening)
        XCTAssertTrue(ShortcutRecorderRow.isRecording)
        XCTAssertEqual(row.button.title, "Type a Shortcut…".localized)

        XCTAssertTrue(row.handle(keyDown("K", code: 40, flags: [.command, .shift])))

        XCTAssertFalse(row.isListening)
        XCTAssertFalse(ShortcutRecorderRow.isRecording)
        let saved = try XCTUnwrap(stored)
        XCTAssertEqual(saved.keyCode, 40)
        XCTAssertTrue(saved.command)
        XCTAssertTrue(saved.shift)
        XCTAssertFalse(saved.option)
        XCTAssertNotEqual(saved.carbonFlags, 0)
        XCTAssertEqual(row.button.title, saved.description)
        XCTAssertEqual(bound.map(\.keyCode), [40], "the registry binds it on prefsChanged")
    }

    // Given a bare letter typed, then the old shortcut stays and nothing is bound
    func test_bareLetterIsRefused() {
        store(combo(40, "k"), for: key)
        row.refresh()
        row.button.performClick(nil)
        row.handle(keyDown("j", code: 38, flags: []))

        XCTAssertFalse(row.isListening)
        XCTAssertEqual(stored?.keyCode, 40)
        XCTAssertEqual(row.button.title, combo(40, "k").description)
    }

    // Given Escape typed, then recording is cancelled and the old shortcut stays
    func test_escapeCancels() {
        store(combo(40, "k"), for: key)
        row.refresh()
        row.button.performClick(nil)
        row.handle(keyDown("\u{1b}", code: 53, flags: []))

        XCTAssertFalse(row.isListening)
        XCTAssertEqual(stored?.keyCode, 40)
        XCTAssertEqual(row.button.title, combo(40, "k").description)
    }

    // Given modifiers pressed then all let go with no key, then it cancels without clearing the shortcut
    func test_releasingAllModifiersCancelsWithoutClearing() {
        store(combo(40, "k"), for: key)
        row.refresh()
        row.button.performClick(nil)

        row.handle(flagsChanged(code: 55, flags: [.command]))
        XCTAssertTrue(row.isListening)
        XCTAssertEqual(row.button.title, "⌘")
        row.handle(flagsChanged(code: 55, flags: []))

        XCTAssertFalse(row.isListening)
        XCTAssertEqual(stored?.keyCode, 40)
    }

    // Given a stored shortcut, when cleared, then the key is removed and the shortcut unbound
    func test_clearRemovesTheStoredShortcut() {
        store(combo(40, "k"), for: key)
        row.refresh()
        row.clear()

        XCTAssertNil(defaults.object(forKey: key))
        XCTAssertTrue(row.clearButton.isHidden)
        XCTAssertEqual(row.button.title, "Set Shortcut".localized)
        XCTAssertFalse(registry.isBound(key))
    }

    // Given a recorder that is not listening, then it takes no events
    func test_ignoresEventsWhenNotListening() {
        XCTAssertFalse(row.handle(keyDown("k", code: 40, flags: [.command])))
        XCTAssertNil(stored)
    }

    // Given another Hidden Bar shortcut with the same combination, then the recorder warns and names it
    func test_clashWithAnotherShortcutShowsAWarning() throws {
        row.button.performClick(nil)
        row.handle(keyDown("K", code: 40, flags: [.command, .shift]))
        XCTAssertNil(row.clashingTitle)
        store(try XCTUnwrap(stored), for: otherKey)
        row.refresh()

        XCTAssertEqual(row.clashingTitle, "Show or hide icons")
        XCTAssertFalse(row.clashIcon.isHidden)
        XCTAssertEqual(row.clashIcon.toolTip, String(format: "Also used by %@".localized, "Show or hide icons"))
    }

    // Given another Hidden Bar shortcut already on a combination
    // When the user records that same combination here
    // Then it is not saved (macOS would refuse it silently), the old shortcut stays, and the warning names the other
    func test_recordingAClashingCombinationIsRefused() {
        store(combo(40, "k", flags: 0x300), for: otherKey)
        let previous = combo(38, "j")
        store(previous, for: key)
        row.refresh()

        row.button.performClick(nil)
        XCTAssertTrue(row.handle(keyDown("K", code: 40, flags: [.command, .shift])))

        XCTAssertEqual(stored, previous, "the clashing combination is not stored")
        XCTAssertFalse(row.isListening)
        XCTAssertEqual(row.button.title, previous.description)
        XCTAssertFalse(row.clashIcon.isHidden)
        XCTAssertEqual(row.clashIcon.toolTip, String(format: "Also used by %@".localized, "Show or hide icons"))

        row.button.performClick(nil)
        row.handle(keyDown("L", code: 37, flags: [.command, .shift]))
        XCTAssertEqual(stored?.keyCode, 37)
        XCTAssertTrue(row.clashIcon.isHidden)
    }

    // Given a combination no other shortcut uses, then there is no warning
    func test_noClashShowsNoWarning() {
        store(combo(38, "j"), for: otherKey)
        row.button.performClick(nil)
        row.handle(keyDown("K", code: 40, flags: [.command, .shift]))

        XCTAssertNil(row.clashingTitle)
        XCTAssertTrue(row.clashIcon.isHidden)
    }

    // Given the General pane, then its Keyboard shortcut row is this control, bound to the old key
    func test_generalPaneUsesTheRecorderBoundToGlobalKey() {
        var context = SettingsContext.live
        context.build = .direct
        context.osMajorVersion = 27
        let pane = PreferencesViewController(context: context)
        _ = pane.view
        XCTAssertEqual(pane.shortcutRecorder.key, UserDefaults.Key.globalKey)
        XCTAssertEqual(pane.shortcutRecorder.button.identifier?.rawValue, UserDefaults.Key.globalKey)
        XCTAssertNotNil(pane.shortcutRecorder.superview, "the recorder sits in the form")
    }
}
