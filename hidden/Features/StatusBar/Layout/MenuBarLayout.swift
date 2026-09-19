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

// AppKit and Accessibility describe the same desktop with different vertical
// origins.  Keeping both rectangles here makes the conversion explicit and,
// more importantly, gives the resolver a stable display identity when two
// screens have different widths or are vertically offset.
struct MenuBarDisplay: Equatable {
    let identifier: String
    let appKitFrame: CGRect
    let accessibilityFrame: CGRect
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
                        displays: [MenuBarDisplay],
                        isLTR: Bool,
                        excludingBundle ownBundle: String?) -> MenuBarLayout? {
        guard let boundaryDisplay = display(containingAppKitPoint: midpoint(of: separatorFrame), in: displays),
              alwaysHiddenSeparatorFrame.map({ display(containingAppKitPoint: midpoint(of: $0), in: displays) == boundaryDisplay }) ?? true else {
            return nil
        }

        var sections: [String: MenuBarSection] = [:]
        for item in inventory {
            guard let bundle = item.bundleIdentifier,
                  bundle != ownBundle,
                  !systemItemOwners.contains(bundle) else { continue }
            // An unassigned third-party item must never be guessed into the
            // hidden side: the native API would otherwise hide an icon the user
            // intentionally kept visible.  The caller fails open in this case.
            guard let itemDisplay = display(containingAccessibilityPoint: midpoint(of: item.frame), in: displays) else {
                return nil
            }
            let section = self.section(of: item.frame,
                                       separatorFrame: projected(separatorFrame, from: boundaryDisplay, to: itemDisplay, isLTR: isLTR),
                                       alwaysHiddenSeparatorFrame: alwaysHiddenSeparatorFrame.map {
                                           projected($0, from: boundaryDisplay, to: itemDisplay, isLTR: isLTR)
                                       },
                                       isLTR: isLTR)
            // One app can own several items, but hiding applies to the whole
            // bundle. The most visible item wins so an icon the user kept visible
            // is never hidden because a sibling sits in the hidden section.
            sections[bundle] = min(sections[bundle] ?? section, section)
        }
        return MenuBarLayout(sections: sections)
    }

    // Menu-bar extras are anchored to the arrow edge of each screen.  Translate
    // the arrow and always-hidden marker by their distance from that edge rather
    // than reusing an absolute x-coordinate from whichever display AppKit chose
    // for the status item window.
    private static func projected(_ frame: CGRect, from source: MenuBarDisplay, to target: MenuBarDisplay, isLTR: Bool) -> CGRect {
        let distanceFromArrowEdge = isLTR
            ? source.appKitFrame.maxX - frame.midX
            : frame.midX - source.appKitFrame.minX
        let projectedMidX = isLTR
            ? target.accessibilityFrame.maxX - distanceFromArrowEdge
            : target.accessibilityFrame.minX + distanceFromArrowEdge
        return CGRect(x: projectedMidX - frame.width / 2, y: 0, width: frame.width, height: frame.height)
    }

    private static func display(containingAppKitPoint point: CGPoint, in displays: [MenuBarDisplay]) -> MenuBarDisplay? {
        return displays.first { $0.appKitFrame.insetBy(dx: -1, dy: -1).contains(point) }
    }

    private static func display(containingAccessibilityPoint point: CGPoint, in displays: [MenuBarDisplay]) -> MenuBarDisplay? {
        return displays.first { $0.accessibilityFrame.insetBy(dx: -1, dy: -1).contains(point) }
    }

    private static func midpoint(of frame: CGRect) -> CGPoint {
        return CGPoint(x: frame.midX, y: frame.midY)
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
