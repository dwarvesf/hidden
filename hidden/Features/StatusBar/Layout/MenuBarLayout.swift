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

// One status item another app owns. On macOS 27 Accessibility exposes no title or
// identifier for these, so the owning bundle and the frame are all there is.
struct MenuBarInventoryItem: Equatable {
    let bundleIdentifier: String?
    let frame: CGRect
}

protocol MenuBarInventoryProviding: AnyObject {
    var isAuthorized: Bool { get }
    func requestAuthorization()
    // Every other app's status items. Only meaningful while nothing is hidden: once
    // a native visibility assertion is active, hidden items report stale frames.
    func snapshot() -> [MenuBarInventoryItem]
}

struct MenuBarLayout: Equatable {
    // One section per owning bundle, because hiding is per bundle.
    var sections: [String: MenuBarSection]

    func bundles(in wanted: Set<MenuBarSection>) -> [String] {
        return sections.filter { wanted.contains($0.value) }.map(\.key).sorted()
    }
}

enum MenuBarLayoutResolver {
    // Bundles whose items are macOS's own controls (clock, Wi-Fi, Control Center...).
    // They cannot be hidden by bundle, so they are left out of the layout and kept
    // visible separately.
    static let systemItemOwners: Set<String> = ["com.apple.MenuBarAgent", "com.apple.controlcenter", "com.apple.systemuiserver"]

    static func resolve(inventory: [MenuBarInventoryItem],
                        separatorFrame: CGRect,
                        alwaysHiddenSeparatorFrame: CGRect?,
                        isLTR: Bool,
                        excludingBundle ownBundle: String?) -> MenuBarLayout {
        var sections: [String: MenuBarSection] = [:]
        for item in inventory {
            guard let bundle = item.bundleIdentifier,
                  bundle != ownBundle,
                  !systemItemOwners.contains(bundle) else { continue }
            let section = self.section(of: item.frame,
                                       separatorFrame: separatorFrame,
                                       alwaysHiddenSeparatorFrame: alwaysHiddenSeparatorFrame,
                                       isLTR: isLTR)
            // One app can own several items, but hiding applies to the whole
            // bundle. The most visible item wins so an icon the user kept visible
            // is never hidden because a sibling sits in the hidden section.
            sections[bundle] = min(sections[bundle] ?? section, section)
        }
        return MenuBarLayout(sections: sections)
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
