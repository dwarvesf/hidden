//
//  ExpandCollapseAction.swift
//  Hidden Bar
//
//  Copyright © 2026 Console Labs. All rights reserved.
//

import AppKit

// What a press on the expand/collapse button should do. Kept as a pure mapping
// so the decision is unit-testable without a live status item or a real NSEvent.
enum ExpandCollapseAction: CaseIterable {
    case toggle
    case contextMenu
    case toggleSeparators
    case toggleWithFullBar
    // A press that is only half a click (a mouse-down or a drag): the action
    // runs on the mouse-up, so nothing happens here.
    case ignore

    // Only a plain click that expands the bar may follow with the arrivals
    // question. A right-click shows the context menu and nothing else.
    var mayShowArrivalsPrompt: Bool { self == .toggle }

    // The context menu is the only thing on screen when it opens: a popover
    // hanging from the arrow closes first instead of vanishing under the menu.
    var closesArrowPopovers: Bool { self == .contextMenu }
}

// What a plain right-click on the arrow does (Settings › Advanced). Before 1.11
// it showed the always-hidden icons; since then it opens the menu. The raw value
// is what Preferences stores.
enum RightClickAction: String, CaseIterable {
    case showMenu
    case showAlwaysHidden

    static let `default`: RightClickAction = .showMenu

    /// Anything unknown or missing reads as the default.
    init(storedValue: String?) {
        self = storedValue.flatMap(RightClickAction.init(rawValue:)) ?? .default
    }
}

enum ExpandCollapseActionResolver {
    // On macOS 27 the mouse-up event a status bar button hands to its action
    // carries empty modifier flags even while Option is held (#434), so the live
    // keyboard state is consulted as well.
    static func isOptionPressed(eventFlags: NSEvent.ModifierFlags?, liveFlags: NSEvent.ModifierFlags) -> Bool {
        return (eventFlags?.contains(.option) ?? false) || liveFlags.contains(.option)
    }

    // Same live-flags fallback as Option, for the one-shot full menu bar click.
    static func isShiftPressed(eventFlags: NSEvent.ModifierFlags?, liveFlags: NSEvent.ModifierFlags) -> Bool {
        return (eventFlags?.contains(.shift) ?? false) || liveFlags.contains(.shift)
    }

    // A nil event type means there is no real NSEvent behind the press, which is
    // what assistive synthesis (VoiceOver AXPress) produces: treat it as a plain
    // left click so VoiceOver users can toggle the bar at all.
    // With right-click set to show the always-hidden icons, the two swap: a
    // right-click toggles them and Option-right-click opens the menu.
    static func action(eventType: NSEvent.EventType?, optionPressed: Bool, shiftPressed: Bool = false,
                       rightClick: RightClickAction = .default) -> ExpandCollapseAction {
        guard let eventType = eventType else { return .toggle }
        switch eventType {
        case .leftMouseDown, .leftMouseDragged, .rightMouseDown, .rightMouseDragged: return .ignore
        default: break
        }
        if eventType == .rightMouseUp && rightClick == .showAlwaysHidden {
            return optionPressed ? .contextMenu : .toggleSeparators
        }
        if optionPressed { return .toggleSeparators }
        switch eventType {
        case .leftMouseUp: return shiftPressed ? .toggleWithFullBar : .toggle
        case .rightMouseUp: return .contextMenu
        default: return .toggleSeparators
        }
    }
}

// What the full menu bar option needs from the app to make it the active one.
// A seam so the choice of API is unit-testable without activating a real app.
protocol FullBarActivating {
    func activateIgnoringOtherApps()
    func activateFromFrontApp()
}

extension NSApplication: FullBarActivating {
    func activateIgnoringOtherApps() {
        activate(ignoringOtherApps: true)
    }

    // From macOS 14 a plain activate() is also ignored when another app is
    // frontmost, so name the front app as the one to take the active state from.
    func activateFromFrontApp() {
        guard #available(macOS 14.0, *) else { return }
        if let front = NSWorkspace.shared.frontmostApplication, front != NSRunningApplication.current,
           NSRunningApplication.current.activate(from: front, options: []) {
            return
        }
        activate()
    }
}

enum FullBarActivation {
    // From macOS 14 activate(ignoringOtherApps:) and a plain activate() are
    // ignored (cooperative activation), so the full menu bar option never took
    // focus and the front app's menus kept the bar (#142). Older systems keep
    // the old call.
    static var usesCooperativeActivation: Bool {
        return ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 14, minorVersion: 0, patchVersion: 0))
    }

    static func activate(_ app: FullBarActivating, cooperative: Bool = usesCooperativeActivation) {
        if cooperative {
            app.activateFromFrontApp()
        } else {
            app.activateIgnoringOtherApps()
        }
    }
}
