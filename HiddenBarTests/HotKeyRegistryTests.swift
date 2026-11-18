//
//  HotKeyRegistryTests.swift
//  HiddenBarTests
//
//  Copyright © 2026 Console Labs. All rights reserved.
//

import XCTest

// The registry compiles into this bundle without the hot key library: a fake
// binder stands in for the Carbon registration.

private final class FakeBinding {}

private final class FakeBinder {
    struct Call {
        let combo: GlobalKeybindPreferences
        let handler: () -> Void
        weak var binding: FakeBinding?
    }

    private(set) var calls: [Call] = []

    func bind(_ combo: GlobalKeybindPreferences, _ handler: @escaping () -> Void) -> AnyObject? {
        let binding = FakeBinding()
        calls.append(Call(combo: combo, handler: handler, binding: binding))
        return binding
    }

    var liveBindings: [GlobalKeybindPreferences] {
        calls.filter { $0.binding != nil }.map(\.combo)
    }
}

private func shortcut(_ characters: String, keyCode: UInt32, command: Bool = true, shift: Bool = false,
                      flags: UInt32 = 0x100) -> GlobalKeybindPreferences {
    GlobalKeybindPreferences(function: false, control: false, command: command, shift: shift, option: false,
                             capsLock: false, carbonFlags: flags | (shift ? 0x200 : 0), characters: characters, keyCode: keyCode)
}

final class HotKeyRegistryTests: XCTestCase {
    private let toggleKey = "globalKey"
    private let findKey = "findHiddenIconShortcut"
    private var defaults: UserDefaults!
    private var center: NotificationCenter!
    private var binder: FakeBinder!
    private var registry: HotKeyRegistry!
    private var suite: String!

    override func setUp() {
        super.setUp()
        suite = "HotKeyRegistryTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        center = NotificationCenter()
        binder = FakeBinder()
        registry = HotKeyRegistry(defaults: defaults, center: center) { [binder] combo, handler in
            binder!.bind(combo, handler)
        }
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func store(_ combo: GlobalKeybindPreferences?, for key: String) {
        if let combo {
            defaults.set(try? JSONEncoder().encode(combo), forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
        center.post(name: .prefsChanged, object: nil)
    }

    // Given a stored shortcut for the expand/collapse key
    // When the key is registered, then the shortcut goes live and runs the handler
    func test_registerBindsTheStoredShortcutAndItsHandlerRuns() {
        let combo = shortcut("k", keyCode: 40)
        store(combo, for: toggleKey)
        var toggled = 0
        registry.register(key: toggleKey) { toggled += 1 }

        XCTAssertEqual(binder.liveBindings, [combo])
        XCTAssertTrue(registry.isBound(toggleKey))
        binder.calls[0].handler()
        XCTAssertEqual(toggled, 1)
    }

    // Given no stored shortcut, when registered, then nothing is bound
    func test_registerWithNoShortcutBindsNothing() {
        registry.register(key: toggleKey) {}
        XCTAssertTrue(binder.calls.isEmpty)
        XCTAssertFalse(registry.isBound(toggleKey))
    }

    // Given a registered key with no shortcut
    // When the preference is written and prefsChanged posts, then it goes live
    func test_prefsChangedBindsAShortcutSetLater() {
        registry.register(key: toggleKey) {}
        let combo = shortcut("k", keyCode: 40)
        store(combo, for: toggleKey)
        XCTAssertEqual(binder.liveBindings, [combo])
    }

    // Given a live shortcut, when the user records another one
    // Then the old binding is released and only the new one stays
    func test_changedShortcutReplacesTheOldBinding() {
        let first = shortcut("k", keyCode: 40)
        let second = shortcut("j", keyCode: 38)
        store(first, for: toggleKey)
        registry.register(key: toggleKey) {}
        store(second, for: toggleKey)

        XCTAssertEqual(binder.calls.count, 2)
        XCTAssertEqual(binder.liveBindings, [second])
    }

    // Given a live shortcut, when it is cleared, then it is unbound
    func test_clearedShortcutIsUnbound() {
        store(shortcut("k", keyCode: 40), for: toggleKey)
        registry.register(key: toggleKey) {}
        XCTAssertTrue(registry.isBound(toggleKey))
        store(nil, for: toggleKey)
        XCTAssertFalse(registry.isBound(toggleKey))
        XCTAssertTrue(binder.liveBindings.isEmpty)
    }

    // Given a live shortcut, when an unrelated preference changes
    // Then it is not bound again
    func test_unrelatedPrefsChangedDoesNotRebind() {
        store(shortcut("k", keyCode: 40), for: toggleKey)
        registry.register(key: toggleKey) {}
        center.post(name: .prefsChanged, object: nil)
        center.post(name: .prefsChanged, object: nil)
        XCTAssertEqual(binder.calls.count, 1)
    }

    // Given two features, when both have a shortcut, then each runs its own handler
    func test_eachKeyKeepsItsOwnHandler() {
        store(shortcut("k", keyCode: 40), for: toggleKey)
        store(shortcut("f", keyCode: 3, shift: true), for: findKey)
        var ran: [String] = []
        registry.register(key: toggleKey) { ran.append("toggle") }
        registry.register(key: findKey) { ran.append("find") }

        XCTAssertEqual(registry.registeredKeys, [findKey, toggleKey])
        binder.calls.forEach { $0.handler() }
        XCTAssertEqual(ran, ["toggle", "find"])
    }

    // Given a key registered twice, then the later handler runs and one binding stays
    func test_registeringAgainReplacesTheHandler() {
        store(shortcut("k", keyCode: 40), for: toggleKey)
        var ran: [String] = []
        registry.register(key: toggleKey) { ran.append("old") }
        registry.register(key: toggleKey) { ran.append("new") }

        XCTAssertEqual(binder.liveBindings.count, 1)
        binder.calls.last?.handler()
        XCTAssertEqual(ran, ["new"])
    }

    // Given a registry reload (an imported preference set), then changes apply
    func test_reloadPicksUpAShortcutWrittenWithoutANotification() {
        registry.register(key: toggleKey) {}
        defaults.set(try? JSONEncoder().encode(shortcut("k", keyCode: 40)), forKey: toggleKey)
        registry.reload()
        XCTAssertTrue(registry.isBound(toggleKey))
    }

    // Given an unregistered key, then its shortcut is no longer listened for
    func test_unregisterStopsListening() {
        store(shortcut("k", keyCode: 40), for: toggleKey)
        registry.register(key: toggleKey) {}
        registry.unregister(key: toggleKey)
        XCTAssertFalse(registry.isBound(toggleKey))
        XCTAssertTrue(binder.liveBindings.isEmpty)
        store(shortcut("j", keyCode: 38), for: toggleKey)
        XCTAssertEqual(binder.calls.count, 1)
    }

    // Given two shortcuts with the same combo, then each names the other as a clash
    func test_sameComboClashesWithTheOtherShortcut() {
        let combo = shortcut("k", keyCode: 40)
        store(combo, for: toggleKey)
        store(combo, for: findKey)
        registry.register(key: toggleKey, title: "Show or hide icons") {}
        registry.register(key: findKey, title: "Find a hidden icon") {}

        XCTAssertEqual(registry.clashingTitle(for: combo, excluding: findKey), "Show or hide icons")
        XCTAssertEqual(registry.clashingTitle(for: combo, excluding: toggleKey), "Find a hidden icon")
    }

    // Given a different key or modifiers, then there is no clash; a key never clashes with itself
    func test_differentComboDoesNotClash() {
        store(shortcut("k", keyCode: 40), for: toggleKey)
        registry.register(key: toggleKey, title: "Show or hide icons") {}
        registry.register(key: findKey, title: "Find a hidden icon") {}

        XCTAssertNil(registry.clashingTitle(for: shortcut("j", keyCode: 38), excluding: findKey))
        XCTAssertNil(registry.clashingTitle(for: shortcut("k", keyCode: 40, shift: true), excluding: findKey))
        XCTAssertNil(registry.clashingTitle(for: shortcut("k", keyCode: 40), excluding: toggleKey))
    }

    // Given a key with no title, then the clash names the preference key
    func test_clashWithoutATitleFallsBackToTheKey() {
        let combo = shortcut("k", keyCode: 40)
        store(combo, for: toggleKey)
        registry.register(key: toggleKey) {}
        XCTAssertEqual(registry.clashingTitle(for: combo, excluding: findKey), toggleKey)
    }

    // Given two shortcuts on one combination (macOS keeps the first and refuses the second silently)
    // When the first is cleared
    // Then the second works: every binding is made again on a change, not skipped as unchanged
    func test_clearingTheOtherShortcutRevivesTheOneThatLostTheClash() {
        let combo = shortcut("k", keyCode: 40)
        let carbon = CarbonLikeBinder()
        let registry = HotKeyRegistry(defaults: defaults, center: center) { carbon.bind($0, $1) }
        store(combo, for: toggleKey)
        store(combo, for: findKey)
        var ran: [String] = []
        registry.register(key: toggleKey, title: "Show or hide icons") { ran.append("toggle") }
        registry.register(key: findKey, title: "Find a hidden icon") { ran.append("find") }
        carbon.fire(combo)
        XCTAssertEqual(ran.count, 1, "one of the two owns the combination")
        let loser = ran[0] == "toggle" ? findKey : toggleKey
        let winner = loser == findKey ? toggleKey : findKey

        store(nil, for: winner)
        ran = []
        carbon.fire(combo)
        XCTAssertEqual(ran, [loser == findKey ? "find" : "toggle"], "the survivor works once the other is cleared")
        XCTAssertTrue(registry.isBound(loser))
    }

    // Given live shortcuts
    // When an unrelated preference changes, then one changes
    // Then the first touches nothing and the second makes every binding again
    func test_onlyAShortcutChangeRebindsEverything() {
        store(shortcut("k", keyCode: 40), for: toggleKey)
        store(shortcut("f", keyCode: 3, shift: true), for: findKey)
        registry.register(key: toggleKey) {}
        registry.register(key: findKey) {}
        XCTAssertEqual(binder.calls.count, 2)
        center.post(name: .prefsChanged, object: nil)
        XCTAssertEqual(binder.calls.count, 2)
        store(shortcut("j", keyCode: 38), for: toggleKey)
        XCTAssertEqual(binder.calls.count, 4)
        XCTAssertEqual(Set(binder.liveBindings.map(\.keyCode)), [38, 3])
    }
}

/// Stands in for Carbon: a combination already held by a live registration is
/// refused silently (the call "succeeds", the handler never fires, even after the
/// holder goes away).
private final class CarbonLikeBinder {
    private final class Binding {
        let combo: GlobalKeybindPreferences
        let handler: () -> Void
        let refused: Bool
        init(_ combo: GlobalKeybindPreferences, refused: Bool, _ handler: @escaping () -> Void) {
            self.combo = combo
            self.refused = refused
            self.handler = handler
        }
    }

    private final class WeakBox {
        weak var value: Binding?
        init(_ value: Binding) { self.value = value }
    }

    private var registered: [WeakBox] = []

    func bind(_ combo: GlobalKeybindPreferences, _ handler: @escaping () -> Void) -> AnyObject? {
        let held = registered.compactMap(\.value).contains { !$0.refused && $0.combo.isSameCombo(as: combo) }
        let binding = Binding(combo, refused: held, handler)
        registered.append(WeakBox(binding))
        return binding
    }

    /// Runs the handler of the live registration that owns the combination.
    func fire(_ combo: GlobalKeybindPreferences) {
        registered.compactMap(\.value).first { !$0.refused && $0.combo.isSameCombo(as: combo) }?.handler()
    }
}
