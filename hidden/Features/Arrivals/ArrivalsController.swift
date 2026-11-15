//
//  ArrivalsController.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

#if HIDDENBAR_NATIVE_VISIBILITY
import AppKit

extension Notification.Name {
    // Posted on the main thread when the waiting arrivals change (a new one, an
    // answer, a lapse). The arrow's dot and the Icons list follow it.
    static let arrivalsChanged = Notification.Name("arrivalsChanged")
}

// What the controller knows about one app, for the prompt.
struct ArrivalInfo {
    let bundle: String
    let name: String
    let icon: NSImage
    let firstSeen: Date
    let isRunning: Bool
    let iconCount: Int
}

// Puts the inbox's decisions to work: it listens for the catalog's arrivals,
// applies the Settings default through `PinnedSectionEdits.set` (the same write
// the Icons list makes, so the engine follows at once), keeps the questions that
// wait under `arrivalsPending`, and applies answers. No window, no banner, no
// permission: the prompt itself is drawn by ArrivalsPresenter, from the arrow.
final class ArrivalsController {
    static let shared = ArrivalsController()

    private(set) var inbox: ArrivalsInbox
    // Items per app in the latest unrestricted read: Docker Desktop shows two.
    private var iconCounts: [String: Int] = [:]

    private let store: UserDefaultsArrivalsPending
    private let center: NotificationCenter
    private let table: MenuBarSectionMemory
    private let choice: () -> NewAppDefault
    private let pinsSections: () -> Bool
    private let lookup: (String) -> MenuBarCatalogEntry?
    private let place: (MenuBarSection, String) -> Void
    private let now: () -> Date
    private var observer: NSObjectProtocol?

    init(defaults: UserDefaults = .standard,
         center: NotificationCenter = .default,
         table: MenuBarSectionMemory = UserDefaultsPinnedSections(defaults: .standard),
         choice: @escaping () -> NewAppDefault = { Preferences.newAppDefaultSection },
         pinsSections: @escaping () -> Bool = { Preferences.pinnedSectionsEnabled },
         lookup: @escaping (String) -> MenuBarCatalogEntry? = { MenuBarItemCatalog.shared.entry(for: $0) },
         place: ((MenuBarSection, String) -> Void)? = nil,
         now: @escaping () -> Date = Date.init) {
        self.store = UserDefaultsArrivalsPending(defaults: defaults)
        self.center = center
        self.table = table
        self.choice = choice
        self.pinsSections = pinsSections
        self.lookup = lookup
        self.place = place ?? { section, bundle in PinnedSectionEdits.set(section, for: bundle, in: table) }
        self.now = now
        inbox = ArrivalsInbox(pending: store.bundles)
    }

    deinit {
        observer.map(center.removeObserver)
    }

    // Starts listening. Safe to call twice.
    func start() {
        guard observer == nil else { return }
        observer = center.addObserver(forName: .menuBarCatalogChanged, object: nil, queue: nil) { [weak self] note in
            let arrivals = note.userInfo?[MenuBarItemCatalog.arrivalsKey] as? [String] ?? []
            self?.catalogChanged(arrivals: arrivals)
        }
        refresh()
    }

    var pending: [String] { inbox.pending }

    // The engine's raw read, before the catalog folds it in: how many icons each app has.
    func noteInventory(_ inventory: [MenuBarInventoryItem]) {
        var counts: [String: Int] = [:]
        for item in inventory {
            if let bundle = item.bundleIdentifier { counts[bundle, default: 0] += 1 }
        }
        iconCounts = counts
    }

    // A read found these apps for the first time (or the catalog republished the latest list).
    func catalogChanged(arrivals: [String]) {
        var next = inbox
        let placements = next.receive(arrivals, choice: choice(), pinsSections: pinsSections(), table: table.sections)
        apply(next, placements: placements)
    }

    // Lapsed questions, and questions about apps the user removed from the Icons list.
    func refresh() {
        var next = inbox
        next.prune(keeping: table.sections)
        let placements = next.expire(now: now(), firstSeen: { self.lookup($0)?.firstSeen }, choice: choice(), table: table.sections)
        apply(next, placements: placements)
    }

    @discardableResult
    func answer(_ bundle: String, _ answer: ArrivalAnswer) -> Bool {
        var next = inbox
        guard let placement = next.answer(bundle, answer) else { return false }
        apply(next, placements: [placement])
        return true
    }

    func answerAll(_ answer: ArrivalAnswer) {
        var next = inbox
        let placements = next.answerAll(answer)
        apply(next, placements: placements)
    }

    // The waiting apps, newest first, as the prompt lists them.
    func waiting() -> [ArrivalInfo] {
        let infos = inbox.pending.map(info(for:))
        return infos.sorted { $0.firstSeen > $1.firstSeen }
    }

    func info(for bundle: String) -> ArrivalInfo {
        let count = max(iconCounts[bundle] ?? 1, 1)
        if let entry = lookup(bundle) {
            return ArrivalInfo(bundle: bundle, name: entry.name, icon: entry.icon, firstSeen: entry.firstSeen,
                               isRunning: entry.isRunning, iconCount: count)
        }
        let resolver = WorkspaceAppResolver()
        return ArrivalInfo(bundle: bundle, name: resolver.name(of: bundle) ?? bundle,
                           icon: resolver.icon(of: bundle) ?? NSWorkspace.shared.icon(for: .applicationBundle),
                           firstSeen: now(), isRunning: resolver.isRunning(bundle), iconCount: count)
    }

    private func apply(_ next: ArrivalsInbox, placements: [ArrivalsInbox.Placement]) {
        let changed = next.pending != inbox.pending
        inbox = next
        if changed { store.bundles = next.pending }
        for placement in placements {
            place(placement.section, placement.bundle)
        }
        if changed { center.post(name: .arrivalsChanged, object: self) }
    }

    #if DEBUG
    // `arrivals-inject <bundle>`: asks about a bundle as if a read had just found
    // it. It is placed visible, as Ask Me does.
    func debugInject(_ bundle: String) {
        var next = inbox
        next.inject(bundle)
        apply(next, placements: [ArrivalsInbox.Placement(bundle: bundle, section: .visible)])
    }

    var debugState: [String: Any] {
        return ["arrivalsPending": inbox.pending, "newAppDefaultSection": choice().rawValue]
    }
    #endif
}
#endif
