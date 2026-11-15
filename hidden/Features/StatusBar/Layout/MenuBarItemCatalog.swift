//
//  MenuBarItemCatalog.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

#if HIDDENBAR_NATIVE_VISIBILITY
import AppKit
import UniformTypeIdentifiers

extension Notification.Name {
    // Posted on the main thread when the catalog's entries change or a read finds
    // apps for the first time. userInfo `MenuBarItemCatalog.arrivalsKey`: the
    // bundle ids that read found for the first time ([String], maybe empty).
    static let menuBarCatalogChanged = Notification.Name("menuBarCatalogChanged")
}

// One app that has a status item in the menu bar.
struct MenuBarCatalogEntry: Equatable {
    let bundleIdentifier: String
    // The running app's name, else the installed bundle's, else the name the
    // Accessibility read gave, else the bundle id.
    let name: String
    // The app's own icon from its bundle: no screen capture.
    let icon: NSImage
    // Where the user keeps it: the pinned-sections table, else the last read.
    let section: MenuBarSection
    let firstSeen: Date
    let isRunning: Bool

    // The icon is an image, not a fact about the app.
    static func == (lhs: MenuBarCatalogEntry, rhs: MenuBarCatalogEntry) -> Bool {
        return lhs.bundleIdentifier == rhs.bundleIdentifier && lhs.name == rhs.name && lhs.section == rhs.section
            && lhs.firstSeen == rhs.firstSeen && lhs.isRunning == rhs.isRunning
    }
}

// What the catalog asks the system about one bundle. A test passes fixtures.
protocol MenuBarAppResolving {
    func name(of bundle: String) -> String?
    func icon(of bundle: String) -> NSImage?
    func isRunning(_ bundle: String) -> Bool
}

struct WorkspaceAppResolver: MenuBarAppResolving {
    func name(of bundle: String) -> String? {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first(where: { !$0.isTerminated }),
           let name = running.localizedName {
            return name
        }
        // "Safari", without ".app" even when Finder shows extensions.
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)?.deletingPathExtension().lastPathComponent
    }

    func icon(of bundle: String) -> NSImage? {
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }

    func isRunning(_ bundle: String) -> Bool {
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundle).contains { !$0.isTerminated }
    }
}

// The menu-bar apps Hidden Bar knows about, for features that list them (a
// palette, an arrivals prompt). It is fed by the reads the engine already makes
// from an unrestricted bar, so it adds no read, no timer and no permission, and
// by app launches and quits, which only change `isRunning`. All of it runs on
// the main thread, where those notifications are posted.
//
// The first run records the apps it finds without announcing them; after that
// an app read for the first time is an arrival.
final class MenuBarItemCatalog {
    static let shared = MenuBarItemCatalog()
    // userInfo key of `.menuBarCatalogChanged`.
    static let arrivalsKey = "arrivals"
    // UserDefaults key: bundle id to the time (seconds since 1970) it was first read.
    static let firstSeenDefaultsKey = UserDefaults.Key.menuBarCatalogFirstSeen

    // Every cataloged app, by name.
    private(set) var entries: [MenuBarCatalogEntry] = []
    // What the latest read found for the first time (empty after one that found none).
    private(set) var arrivals: [String] = []

    private var state: MenuBarCatalogState
    private let defaults: UserDefaults
    private let center: NotificationCenter
    private let resolver: MenuBarAppResolving
    private let pinnedTable: () -> [String: MenuBarSection]
    private let now: () -> Date
    private var icons: [String: NSImage] = [:]
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init(defaults: UserDefaults = .standard,
         center: NotificationCenter = .default,
         resolver: MenuBarAppResolving = WorkspaceAppResolver(),
         pinnedTable: @escaping () -> [String: MenuBarSection] = { UserDefaultsPinnedSections().sections },
         now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.center = center
        self.resolver = resolver
        self.pinnedTable = pinnedTable
        self.now = now
        let stored = defaults.dictionary(forKey: Self.firstSeenDefaultsKey) as? [String: Double]
        state = MenuBarCatalogState(firstSeen: stored.map { $0.mapValues { Date(timeIntervalSince1970: $0) } })
        state.apply(table: pinnedTable())
        entries = makeEntries()
        observers.append((center, center.addObserver(forName: .pinnedSectionsChanged, object: nil, queue: nil) { [weak self] _ in
            self?.pinnedSectionsChanged()
        }))
    }

    deinit {
        observers.forEach { center, observer in center.removeObserver(observer) }
    }

    func entry(for bundle: String) -> MenuBarCatalogEntry? {
        return entries.first { $0.bundleIdentifier == bundle }
    }

    // One read of the menu bar taken while nothing was hidden. `inventory` is
    // the raw Accessibility list, for the names of apps that are not installed.
    func record(layout: MenuBarLayout, inventory: [MenuBarInventoryItem]) {
        var names: [String: String] = [:]
        for item in inventory {
            if let bundle = item.bundleIdentifier, let owner = item.ownerName, names[bundle] == nil {
                names[bundle] = owner
            }
        }
        arrivals = state.apply(read: layout.sections, ownerNames: names, table: pinnedTable(), now: now())
        defaults.set(state.firstSeen.mapValues(\.timeIntervalSince1970), forKey: Self.firstSeenDefaultsKey)
        publish(forced: !arrivals.isEmpty)
    }

    // Apps started or quit since the last look: only `isRunning` can change.
    func refreshRunning() {
        publish(forced: false)
    }

    // Keeps `isRunning` current as apps start and quit. Pass NSWorkspace's
    // center and the engine's AgentLaunchNotifications, which post the same names.
    func observeLaunches(on centers: [NotificationCenter]) {
        for launchCenter in centers {
            for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
                observers.append((launchCenter, launchCenter.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                    self?.refreshRunning()
                }))
            }
        }
    }

    private func pinnedSectionsChanged() {
        state.apply(table: pinnedTable())
        publish(forced: false)
    }

    private func publish(forced: Bool) {
        let rebuilt = makeEntries()
        let changed = rebuilt != entries
        entries = rebuilt
        guard changed || forced else { return }
        center.post(name: .menuBarCatalogChanged, object: self, userInfo: [Self.arrivalsKey: arrivals])
    }

    private func makeEntries() -> [MenuBarCatalogEntry] {
        return state.bundles.map { bundle in
            MenuBarCatalogEntry(bundleIdentifier: bundle,
                                name: resolver.name(of: bundle) ?? state.ownerNames[bundle] ?? bundle,
                                icon: icon(of: bundle),
                                section: state.sections[bundle] ?? .visible,
                                firstSeen: state.firstSeen[bundle] ?? now(),
                                isRunning: resolver.isRunning(bundle))
        }.sorted {
            let order = $0.name.localizedCaseInsensitiveCompare($1.name)
            return order == .orderedSame ? $0.bundleIdentifier < $1.bundleIdentifier : order == .orderedAscending
        }
    }

    private func icon(of bundle: String) -> NSImage {
        if let cached = icons[bundle] { return cached }
        let icon = resolver.icon(of: bundle) ?? NSWorkspace.shared.icon(for: .applicationBundle)
        icons[bundle] = icon
        return icon
    }
}

#if DEBUG
extension MenuBarItemCatalog {
    // The `dump-inventory` debug hook writes this: the catalog as JSON.
    func debugJSON() throws -> Data {
        let formatter = ISO8601DateFormatter()
        let rows: [[String: Any]] = entries.map { entry in
            ["bundleIdentifier": entry.bundleIdentifier,
             "name": entry.name,
             "section": String(describing: entry.section),
             "firstSeen": formatter.string(from: entry.firstSeen),
             "isRunning": entry.isRunning]
        }
        let document: [String: Any] = ["entries": rows, "arrivals": arrivals,
                                       "writtenAt": Date().timeIntervalSince1970]
        return try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
    }
}
#endif
#endif
