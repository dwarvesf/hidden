//
//  HotKeyRegistry.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import Foundation

/// Every global shortcut Hidden Bar listens for, keyed by the preference that
/// stores it. A feature adds one with a single `register(key:handler:)` call and
/// the registry keeps the live binding in step with the stored shortcut: it
/// re-reads on `.prefsChanged`, so a recorder only has to write the preference.
///
/// The registry never imports the hot key library; `bind` is the one place that
/// does (see `HotKeyRegistry.shared`), which keeps this type testable with a fake.
final class HotKeyRegistry {
    typealias Handler = () -> Void
    /// Makes a live binding for a shortcut. The returned object is the binding:
    /// the registry keeps it while the shortcut stays, and drops it to unbind.
    typealias Binder = (GlobalKeybindPreferences, @escaping Handler) -> AnyObject?

    private struct Entry {
        let title: String?
        let handler: Handler
        var combo: GlobalKeybindPreferences?
        var binding: AnyObject?
    }

    private var entries: [String: Entry] = [:]
    private let defaults: UserDefaults
    private let bind: Binder
    private let center: NotificationCenter
    private var observer: NSObjectProtocol?

    init(defaults: UserDefaults = AppDefaults.store, center: NotificationCenter = .default, bind: @escaping Binder) {
        self.defaults = defaults
        self.bind = bind
        self.center = center
        observer = center.addObserver(forName: .prefsChanged, object: nil, queue: nil) { [weak self] _ in
            self?.reload()
        }
    }

    deinit {
        observer.map(center.removeObserver)
    }

    /// Listens for the shortcut stored under `key` (a `Data` preference holding
    /// `GlobalKeybindPreferences` JSON). `title` names it in a clash warning.
    /// Registering a key again replaces its handler.
    func register(key: String, title: String? = nil, handler: @escaping Handler) {
        entries[key] = Entry(title: title, handler: handler, combo: nil, binding: nil)
        rebind(key)
    }

    func unregister(key: String) {
        entries[key] = nil
    }

    /// Re-reads every registered preference. When any shortcut changed, every
    /// binding is dropped and made again: macOS refuses a second registration of a
    /// combination silently, so a shortcut that lost a clash stays dead after the
    /// other one is cleared unless it registers again. Unchanged, nothing is touched.
    func reload() {
        guard entries.keys.contains(where: { changed($0) }) else { return }
        for key in entries.keys {
            entries[key]?.binding = nil
            entries[key]?.combo = nil
        }
        for key in entries.keys {
            rebind(key)
        }
    }

    var registeredKeys: [String] { entries.keys.sorted() }

    /// The shortcut stored under `key`, whether or not it is registered.
    func shortcut(for key: String) -> GlobalKeybindPreferences? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(GlobalKeybindPreferences.self, from: $0) }
    }

    /// True while `key` has a live binding.
    func isBound(_ key: String) -> Bool {
        entries[key]?.binding != nil
    }

    /// The name of another registered shortcut that already uses `combo`, if any.
    func clashingTitle(for combo: GlobalKeybindPreferences, excluding key: String) -> String? {
        for other in registeredKeys where other != key {
            guard let stored = shortcut(for: other), stored.isSameCombo(as: combo) else { continue }
            return entries[other]?.title ?? other
        }
        return nil
    }

    private func changed(_ key: String) -> Bool {
        guard let entry = entries[key] else { return false }
        let stored = shortcut(for: key)
        return stored != entry.combo || (stored == nil) != (entry.binding == nil)
    }

    private func rebind(_ key: String) {
        guard let entry = entries[key] else { return }
        let stored = shortcut(for: key)
        if !changed(key) { return }
        // Unbind first: two live bindings for one combo would clash.
        entries[key]?.binding = nil
        entries[key]?.combo = stored
        if let stored {
            entries[key]?.binding = bind(stored, entry.handler)
        }
    }
}
