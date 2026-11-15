//
//  MenuBarLayout.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import AppKit

// Which of Hidden Bar's sections a menu-bar item belongs to, read from where the
// user ⌘-dragged it relative to the separators:
//
//     LTR:  [ always hidden ] | [ hidden ] | > [ visible ]
//                             ^            ^
//                  always-hidden separator  separator (beside the arrow)
enum MenuBarSection: Int, Comparable {
    case visible
    case hidden
    case alwaysHidden

    static func < (lhs: MenuBarSection, rhs: MenuBarSection) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

// One status item another app owns. Apps' items expose no title or identifier
// on macOS 27, so the owning bundle and the frame are all there is. macOS's own
// extras do name themselves (com.apple.menuextra.focusmode...).
struct MenuBarInventoryItem: Equatable {
    let bundleIdentifier: String?
    let frame: CGRect
    // Set only for items of systemItemOwners.
    var systemIdentifier: String? = nil
    // The owner did not answer Accessibility in time, so the frame is unknown.
    var isUnreadable: Bool = false
    var ownerName: String? = nil
}

// One connected display. Every display has its own menu bar, but AppKit hands
// over the arrow's frame on whichever display it is drawn on right now, while
// Accessibility may list the other apps' items on another one. AppKit frames
// start at the primary display's bottom-left, Accessibility frames at its
// top-left, so each display carries both.
struct MenuBarDisplay: Equatable {
    let appKitFrame: CGRect
    let accessibilityFrame: CGRect

    init(appKitFrame: CGRect, primaryDisplayHeight: CGFloat) {
        self.appKitFrame = appKitFrame
        accessibilityFrame = CGRect(x: appKitFrame.minX, y: primaryDisplayHeight - appKitFrame.maxY,
                                    width: appKitFrame.width, height: appKitFrame.height)
    }

    static func current() -> [MenuBarDisplay] {
        return displays(screenFrames: NSScreen.screens.map(\.frame))
    }

    // The primary display is the first screen. It is not always the topmost
    // one: a display arranged above it has a negative Accessibility y.
    static func displays(screenFrames: [CGRect]) -> [MenuBarDisplay] {
        guard let primary = screenFrames.first else { return [] }
        return screenFrames.map { MenuBarDisplay(appKitFrame: $0, primaryDisplayHeight: primary.height) }
    }

    static func containing(appKitFrame frame: CGRect, in displays: [MenuBarDisplay]) -> MenuBarDisplay? {
        let point = CGPoint(x: frame.midX, y: frame.midY)
        return displays.first { $0.appKitFrame.contains(point) }
    }

    static func containing(accessibilityFrame frame: CGRect, in displays: [MenuBarDisplay]) -> MenuBarDisplay? {
        let point = CGPoint(x: frame.midX, y: frame.midY)
        return displays.first { $0.accessibilityFrame.contains(point) }
    }
}

protocol MenuBarInventoryProviding: AnyObject {
    var isAuthorized: Bool { get }
    func requestAuthorization()
    // Every other app's status items, delivered on the main queue. Only meaningful
    // while nothing is hidden: once a native visibility assertion is active,
    // hidden items report stale frames.
    func snapshot(completion: @escaping ([MenuBarInventoryItem]) -> Void)
}

// The section each app was last read in, per bundle.
protocol MenuBarSectionMemory: AnyObject {
    var sections: [String: MenuBarSection] { get set }
}

final class InMemorySectionMemory: MenuBarSectionMemory {
    var sections: [String: MenuBarSection] = [:]
}

// Kept across launches of Hidden Bar, so login items that start after it
// return to the section they were in.
final class UserDefaultsSectionMemory: MenuBarSectionMemory {
    static let key = "nativeVisibilityLastSections"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var sections: [String: MenuBarSection] {
        get {
            let stored = defaults.dictionary(forKey: Self.key) as? [String: Int] ?? [:]
            return stored.compactMapValues(MenuBarSection.init(rawValue:))
        }
        set {
            defaults.set(newValue.mapValues(\.rawValue), forKey: Self.key)
        }
    }
}

// Pinned sections (beta, macOS 27 direct build): the section the user chose
// for each app, which macOS's placement of a new or relaunched icon no longer
// changes. Until it is first written it reads as the sections each app was
// last read in, so turning the beta on keeps every app where it was.
final class UserDefaultsPinnedSections: MenuBarSectionMemory {
    static let key = "pinnedSections"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var sections: [String: MenuBarSection] {
        get {
            guard let stored = defaults.dictionary(forKey: Self.key) as? [String: Int] else {
                return UserDefaultsSectionMemory(defaults: defaults).sections
            }
            return stored.compactMapValues(MenuBarSection.init(rawValue:))
        }
        set {
            defaults.set(newValue.mapValues(\.rawValue), forKey: Self.key)
        }
    }
}

enum PinnedSectionResolver {
    // Where an app that starts with no pinned section goes.
    static let newAppSection: MenuBarSection = .visible

    // Turns one read of the bar into the sections to apply, and edits the table
    // from it. A position is the user's choice only when it changed since the
    // app was last read and the app did not start meanwhile: macOS puts a new
    // or relaunched icon far left, wherever the user had it. `observed` is the
    // section each app was last read in; it follows every read.
    static func resolve(read: [String: MenuBarSection],
                        launchedSinceRead: Set<String>,
                        observed: inout [String: MenuBarSection],
                        table: inout [String: MenuBarSection]) -> [String: MenuBarSection] {
        var resolved: [String: MenuBarSection] = [:]
        for (bundle, position) in read {
            let launched = launchedSinceRead.contains(bundle)
            let moved = observed[bundle].map { $0 != position } ?? false
            switch table[bundle] {
            case nil:
                table[bundle] = launched ? newAppSection : position
            case .some(_) where moved && !launched:
                table[bundle] = position
            case .some:
                break
            }
            observed[bundle] = position
            resolved[bundle] = table[bundle]
        }
        return resolved
    }

    static func resetAllToVisible(_ table: [String: MenuBarSection]) -> [String: MenuBarSection] {
        return table.mapValues { _ in .visible }
    }
}

// Edits from Preferences (and the debug hooks). The engine applies them when
// the controller passes on `.pinnedSectionsChanged`.
enum PinnedSectionEdits {
    static func set(_ section: MenuBarSection, for bundle: String, in table: MenuBarSectionMemory) {
        table.sections[bundle] = section
        NotificationCenter.default.post(name: .pinnedSectionsChanged, object: nil)
    }

    static func resetAllToVisible(in table: MenuBarSectionMemory) {
        table.sections = PinnedSectionResolver.resetAllToVisible(table.sections)
        NotificationCenter.default.post(name: .pinnedSectionsChanged, object: nil)
    }
}

// The rows of the Preferences "Menu bar apps" list: every app the table
// knows, by name. `name` is nil for an app that is not installed any more.
enum PinnedSectionsList {
    struct Entry: Equatable {
        let bundle: String
        let name: String
        let section: MenuBarSection
    }

    static func entries(table: [String: MenuBarSection], name: (String) -> String?) -> [Entry] {
        return table.map { bundle, section in
            let label = bundle == MenuBarLayoutResolver.systemExtrasBundle ? "macOS extras (Focus, Now Playing...)" : (name(bundle) ?? bundle)
            return Entry(bundle: bundle, name: label, section: section)
        }.sorted {
            let order = $0.name.localizedCaseInsensitiveCompare($1.name)
            return order == .orderedSame ? $0.bundle < $1.bundle : order == .orderedAscending
        }
    }
}

extension Notification.Name {
    // Posted on the main queue after Preferences edited the pinned sections.
    static let pinnedSectionsChanged = Notification.Name("pinnedSectionsChanged")
}

struct MenuBarLayout: Equatable {
    // One section per owning bundle, because hiding is per bundle.
    var sections: [String: MenuBarSection]
    // Visible-section items whose owner has no bundle id. The allow-list cannot
    // name them, so any restriction would hide them.
    var unnameableVisibleItems: [String] = []
    // Visible-section system extras that no system item identifier covers. Only
    // their bundle can try to keep them, so the engine checks they stay shown.
    var unprovenVisibleSystemItems: [String] = []
    // The active display's menu bar overflowed (a narrow display), and macOS
    // lists only the items that fit, so apps are missing from `sections`.
    var isIncomplete = false

    // An incomplete read with the apps it missed taken from an earlier read.
    func fillingIn(from earlier: MenuBarLayout) -> MenuBarLayout {
        var layout = self
        layout.sections.merge(earlier.sections) { current, _ in current }
        return layout
    }

    func bundles(in wanted: Set<MenuBarSection>) -> [String] {
        return sections.filter { wanted.contains($0.value) }.map(\.key).sorted()
    }

    // Why nothing may be hidden with this layout: fail open rather than hide an
    // item the user put in the visible section.
    func reasonToKeepBarWhole(unkeepableSystemItems: Set<String>) -> String? {
        if !unnameableVisibleItems.isEmpty {
            return "items right of the arrow have no bundle id, so macOS cannot be told to keep them: \(unnameableVisibleItems)"
        }
        let unkeepable = unprovenVisibleSystemItems.filter(unkeepableSystemItems.contains)
        if !unkeepable.isEmpty {
            return "macOS hides these system items while hiding anything, and they sit right of the arrow: \(unkeepable)"
        }
        return nil
    }
}

enum MenuBarLayoutResolver {
    // Bundles whose items are macOS's own controls protected by system item
    // identifiers (clock, Wi-Fi, Control Center...). They cannot be hidden by
    // bundle, so they are left out of the layout and kept visible separately.
    // SystemUIServer is not one of them: its legacy Menu Extras (Time
    // Machine...) carry no system item identifier and can only stay visible
    // through the per-bundle allow list, so they are sectioned by position like
    // any other app.
    static let systemItemOwners: Set<String> = ["com.apple.MenuBarAgent", "com.apple.controlcenter"]

    // The extras NativeVisibilityEngine.systemItemsToKeep covers. On 27.2 the
    // system item identifiers are battery, bluetooth, clock, displays, keyboard,
    // volume, wifi, primaryBentoBox (Control Center) and screenMirroring.
    static let extrasKeptBySystemItem: Set<String> = [
        "com.apple.menuextra.battery", "com.apple.menuextra.bluetooth", "com.apple.menuextra.clock",
        "com.apple.menuextra.display", "com.apple.menuextra.textinput", "com.apple.menuextra.sound",
        "com.apple.menuextra.wifi", "com.apple.menuextra.controlcenter", "com.apple.menuextra.screenmirroring",
    ]

    // Every other system extra (Focus, Now Playing, Siri, Stage Manager...) is
    // drawn by Control Center, so its bundle is the only name that can try to
    // keep them visible.
    static let systemExtrasBundle = "com.apple.controlcenter"

    // The chevron macOS 27 puts in a menu bar too narrow for every item.
    static let overflowIndicator = "menu-bar-overflow-indicator"

    static func resolve(inventory: [MenuBarInventoryItem],
                        separatorFrame: CGRect,
                        alwaysHiddenSeparatorFrame: CGRect?,
                        displays: [MenuBarDisplay] = [],
                        isLTR: Bool,
                        excludingBundle ownBundle: String?) -> MenuBarLayout {
        var layout = MenuBarLayout(sections: [:])
        // With no display list, or an arrow on none of them, every frame is
        // taken as being on the arrow's display, as on a single display.
        let arrowDisplay = MenuBarDisplay.containing(appKitFrame: separatorFrame, in: displays)
        for item in inventory {
            if let ownBundle = ownBundle, item.bundleIdentifier == ownBundle { continue }
            let section: MenuBarSection
            if item.isUnreadable {
                // Where an unreadable app's items sit is unknown: count them visible.
                section = .visible
            } else if let arrowDisplay = arrowDisplay {
                if let itemDisplay = MenuBarDisplay.containing(accessibilityFrame: item.frame, in: displays) {
                    section = self.section(of: item.frame,
                                           separatorFrame: projected(separatorFrame, from: arrowDisplay, to: itemDisplay, isLTR: isLTR),
                                           alwaysHiddenSeparatorFrame: alwaysHiddenSeparatorFrame.map {
                                               projected($0, from: arrowDisplay, to: itemDisplay, isLTR: isLTR)
                                           },
                                           isLTR: isLTR)
                } else {
                    // On no display (pushed off a narrow one, mid-reflow): its
                    // side is unknown, so it counts visible, like an unreadable one.
                    section = .visible
                }
            } else {
                section = self.section(of: item.frame,
                                       separatorFrame: separatorFrame,
                                       alwaysHiddenSeparatorFrame: alwaysHiddenSeparatorFrame,
                                       isLTR: isLTR)
            }
            guard var key = item.bundleIdentifier else {
                if section == .visible {
                    layout.unnameableVisibleItems.append("\(item.ownerName ?? "unknown owner") at x=\(Int(item.frame.midX))")
                }
                continue
            }
            if systemItemOwners.contains(key), item.systemIdentifier == overflowIndicator {
                layout.isIncomplete = true
                continue
            }
            if systemItemOwners.contains(key) {
                // Unidentified ones are assumed covered by system item identifiers.
                guard let identifier = item.systemIdentifier,
                      !extrasKeptBySystemItem.contains(identifier) else { continue }
                if section == .visible {
                    layout.unprovenVisibleSystemItems.append(identifier)
                }
                key = systemExtrasBundle
            }
            // One app can own several items, but hiding applies to the whole
            // bundle. The most visible item wins so an icon the user kept visible
            // is never hidden because a sibling sits in the hidden section.
            layout.sections[key] = min(layout.sections[key] ?? section, section)
        }
        return layout
    }

    // Status items line up from the arrow's edge of each display (the right
    // edge left to right), so the same item keeps its distance from that edge
    // on every display. Moves a separator frame from the display AppKit drew it
    // on to the one an item was listed on, keeping that distance.
    static func projected(_ frame: CGRect, from source: MenuBarDisplay, to target: MenuBarDisplay, isLTR: Bool) -> CGRect {
        guard source != target else { return frame }
        let dx = isLTR ? target.appKitFrame.maxX - source.appKitFrame.maxX
                       : target.appKitFrame.minX - source.appKitFrame.minX
        return frame.offsetBy(dx: dx, dy: 0)
    }

    // Hidden system extras drop out of Accessibility, unlike apps' items. With
    // no system extra listed at all (the clock always is), Accessibility is not
    // answering, for one while the screen is locked: nothing counts as missing.
    static func missingSystemItems(_ expected: [String], in inventory: [MenuBarInventoryItem]) -> [String] {
        let present = Set(inventory.compactMap(\.systemIdentifier))
        guard !present.isEmpty else { return [] }
        return expected.filter { !present.contains($0) }
    }

    static func section(of frame: CGRect,
                        separatorFrame: CGRect,
                        alwaysHiddenSeparatorFrame: CGRect?,
                        isLTR: Bool) -> MenuBarSection {
        // Distance toward the arrow side: positive means on the visible side.
        func towardArrow(_ x: CGFloat, from boundary: CGRect) -> CGFloat {
            return isLTR ? x - boundary.midX : boundary.midX - x
        }
        if towardArrow(frame.midX, from: separatorFrame) > 0 {
            return .visible
        }
        if let alwaysHidden = alwaysHiddenSeparatorFrame,
           towardArrow(frame.midX, from: alwaysHidden) < 0 {
            return .alwaysHidden
        }
        return .hidden
    }
}
