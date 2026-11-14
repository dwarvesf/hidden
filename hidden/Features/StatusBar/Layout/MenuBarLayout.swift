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

protocol MenuBarInventoryProviding: AnyObject {
    var isAuthorized: Bool { get }
    func requestAuthorization()
    // Every other app's status items, delivered on the main queue. Only meaningful
    // while nothing is hidden: once a native visibility assertion is active,
    // hidden items report stale frames.
    func snapshot(completion: @escaping ([MenuBarInventoryItem]) -> Void)
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

    static func resolve(inventory: [MenuBarInventoryItem],
                        separatorFrame: CGRect,
                        alwaysHiddenSeparatorFrame: CGRect?,
                        isLTR: Bool,
                        excludingBundle ownBundle: String?) -> MenuBarLayout {
        var layout = MenuBarLayout(sections: [:])
        for item in inventory {
            if let ownBundle = ownBundle, item.bundleIdentifier == ownBundle { continue }
            // Where an unreadable app's items sit is unknown: count them visible.
            let section = item.isUnreadable ? .visible : self.section(of: item.frame,
                                                                      separatorFrame: separatorFrame,
                                                                      alwaysHiddenSeparatorFrame: alwaysHiddenSeparatorFrame,
                                                                      isLTR: isLTR)
            guard var key = item.bundleIdentifier else {
                if section == .visible {
                    layout.unnameableVisibleItems.append("\(item.ownerName ?? "unknown owner") at x=\(Int(item.frame.midX))")
                }
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
