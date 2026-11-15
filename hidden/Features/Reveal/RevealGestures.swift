//
//  RevealGestures.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import CoreGraphics
import Foundation

// The decisions behind "reveal without aiming": what a scroll, a click and a
// pointer shake have to look like before they show the hidden icons, and when
// each one is ignored. Free of events, windows and prefs so both test bundles
// can check every rule; RevealController feeds these types and acts on them.

enum RevealTrigger: String, CaseIterable {
    case scroll
    case click
    case shake
}

/// What sits under the pointer in the menu bar.
enum HitTarget: Equatable {
    /// Bare menu bar: no icon and no menu title.
    case emptySpace
    /// A title of the menu bar owner's menus (File, Edit, ...).
    case menuTitle
    /// Another app's or the system's menu bar icon.
    case statusItem
    /// Accessibility is unavailable or gave no usable answer.
    case unknown
}

/// Thresholds in one place so tuning never touches the logic.
enum RevealTuning {
    /// Vertical scroll travel, in points, before a scroll counts as a gesture.
    static let scrollThreshold: CGFloat = 8
    /// A pause this long ends a scroll gesture; the next one counts afresh.
    static let scrollQuietGap: TimeInterval = 0.3
    /// A wheel without precise deltas reports lines, not points.
    static let scrollLineHeight: CGFloat = 10
    /// Three direction reversals ...
    static let shakeReversals = 3
    /// ... inside this many seconds ...
    static let shakeWindow: TimeInterval = 0.6
    /// ... each swing at least this wide, in points.
    static let shakeMinSwing: CGFloat = 12
    /// After a shake fires, ignore the pointer for this long.
    static let shakeCooldown: TimeInterval = 1.0
}

enum ScrollRevealAction: Equatable {
    case show
    case hide
}

/// Turns a stream of scroll deltas into one `show` (scroll down) or `hide`
/// (scroll up) per gesture. `deltaY` follows AppKit's `scrollingDeltaY` in
/// content terms: negative when the content moves up, which is a scroll down,
/// whatever the natural-scrolling setting.
struct ScrollRevealDetector {
    private var accumulated: CGFloat = 0
    private var lastEventTime: TimeInterval?
    private var firedThisGesture = false

    mutating func reset() {
        accumulated = 0
        lastEventTime = nil
        firedThisGesture = false
    }

    mutating func feed(deltaY: CGFloat, at time: TimeInterval, isMomentum: Bool = false) -> ScrollRevealAction? {
        // Momentum after the fingers lift must not start a second gesture.
        guard !isMomentum, deltaY != 0 else { return nil }
        if let last = lastEventTime, time - last > RevealTuning.scrollQuietGap {
            accumulated = 0
            firedThisGesture = false
        }
        lastEventTime = time
        guard !firedThisGesture else { return nil }
        if accumulated != 0, (accumulated < 0) != (deltaY < 0) {
            accumulated = 0
        }
        accumulated += deltaY
        if accumulated <= -RevealTuning.scrollThreshold {
            return fire(.show)
        }
        if accumulated >= RevealTuning.scrollThreshold {
            return fire(.hide)
        }
        return nil
    }

    private mutating func fire(_ action: ScrollRevealAction) -> ScrollRevealAction {
        accumulated = 0
        firedThisGesture = true
        return action
    }
}

/// Fires when the pointer swings left and right quickly inside the menu bar.
/// Only moves count (not drags), and only while the pointer is in the band, so
/// a window dragged along the top never triggers it.
struct ShakeDetector {
    private var direction = 0
    private var extreme: CGFloat?
    private var reversalTimes: [TimeInterval] = []
    private var quietUntil: TimeInterval = 0

    mutating func reset() {
        direction = 0
        extreme = nil
        reversalTimes.removeAll()
    }

    /// True on the move that completes a shake.
    mutating func feed(x: CGFloat, at time: TimeInterval, inBand: Bool) -> Bool {
        guard inBand else {
            reset()
            return false
        }
        guard time >= quietUntil else { return false }
        guard let anchor = extreme else {
            extreme = x
            return false
        }
        let swing = RevealTuning.shakeMinSwing
        if direction == 0 {
            if x - anchor >= swing {
                direction = 1
                extreme = x
            } else if anchor - x >= swing {
                direction = -1
                extreme = x
            }
            return false
        }
        if (x - anchor) * CGFloat(direction) > 0 {
            extreme = x
            return false
        }
        guard (anchor - x) * CGFloat(direction) >= swing else { return false }
        direction = -direction
        extreme = x
        reversalTimes.append(time)
        reversalTimes.removeAll { time - $0 > RevealTuning.shakeWindow }
        guard reversalTimes.count >= RevealTuning.shakeReversals else { return false }
        reset()
        quietUntil = time + RevealTuning.shakeCooldown
        return true
    }
}

/// One screen's menu bar strip, in AppKit coordinates (origin bottom left).
struct ScreenBand: Equatable {
    var frame: CGRect
    var visibleFrame: CGRect
    /// Horizontal extent of the camera housing on a notched screen.
    var notchGap: ClosedRange<CGFloat>?

    /// The strip between `visibleFrame` and the top of the screen, which is the
    /// menu bar's exact height. Nil when the bar is hidden (a full-screen app
    /// leaves no strip), so nothing counts there until the bar slides down.
    var rect: CGRect? {
        let height = frame.maxY - visibleFrame.maxY
        guard height >= 1 else { return nil }
        return CGRect(x: frame.minX, y: visibleFrame.maxY, width: frame.width, height: height)
    }

    func contains(_ point: CGPoint) -> Bool {
        guard let rect = rect else { return false }
        return point.x >= rect.minX && point.x <= rect.maxX && point.y >= rect.minY && point.y <= rect.maxY
    }

    func isInNotch(_ point: CGPoint) -> Bool {
        contains(point) && (notchGap?.contains(point.x) ?? false)
    }
}

enum MenuBarBand {
    /// Any screen's menu bar strip holds the point.
    static func contains(_ point: CGPoint, in screens: [ScreenBand]) -> Bool {
        screens.contains { $0.contains(point) }
    }

    static func isInNotch(_ point: CGPoint, in screens: [ScreenBand]) -> Bool {
        screens.contains { $0.isInNotch(point) }
    }

    /// Accessibility works in a top-left origin anchored on the primary screen.
    static func accessibilityPoint(fromAppKit point: CGPoint, primaryScreenHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    }
}

/// What an Accessibility read at the pointer returned.
struct HitProbe: Equatable {
    var role: String?
    var ownerPID: Int32?
    var frontmostPID: Int32?
    /// The app whose menus the menu bar shows. It differs from the frontmost app
    /// when that one has no menus (an agent app), so menu titles belong to this one.
    var menuBarOwnerPID: Int32?
}

enum HitClassifier {
    /// The menu bar itself under the pointer means nothing else is there. A menu
    /// bar item owned by the app that owns the menu bar is one of its menu titles; any other
    /// owner is an icon. Everything else is unknown, which never counts as empty.
    static func target(for probe: HitProbe) -> HitTarget {
        guard let role = probe.role else { return .unknown }
        switch role {
        case "AXMenuBar":
            return .emptySpace
        case "AXMenuBarItem", "AXMenuExtra", "AXMenuItem":
            guard let owner = probe.ownerPID, owner == probe.menuBarOwnerPID else { return .statusItem }
            return .menuTitle
        default:
            return .unknown
        }
    }
}

enum RevealPolicy {
    /// Whether a recognised gesture may show the icons.
    /// - A click counts only on empty space: a menu title or an icon keeps its click.
    /// - A scroll counts anywhere except over an icon, whose app may use scroll itself.
    ///   Without Accessibility the target is unknown and the scroll counts.
    /// - A shake needs no hit test.
    static func allowsShow(_ trigger: RevealTrigger, target: HitTarget, barIsCollapsed: Bool, ownMenuIsOpen: Bool) -> Bool {
        guard barIsCollapsed, !ownMenuIsOpen else { return false }
        switch trigger {
        case .click: return target == .emptySpace
        case .scroll: return target != .statusItem
        case .shake: return true
        }
    }

    /// Scroll up hides, except over an icon.
    static func allowsScrollHide(target: HitTarget, barIsCollapsed: Bool, ownMenuIsOpen: Bool) -> Bool {
        !barIsCollapsed && !ownMenuIsOpen && target != .statusItem
    }

    /// A click away from the menu bar hides what a gesture revealed.
    static func allowsOffBarHide(clickIsInMenuBar: Bool, revealedByGesture: Bool, barIsCollapsed: Bool, ownMenuIsOpen: Bool) -> Bool {
        !clickIsInMenuBar && revealedByGesture && !barIsCollapsed && !ownMenuIsOpen
    }
}
