//
//  ExpandCollapseAction.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
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
    static func action(eventType: NSEvent.EventType?, optionPressed: Bool, shiftPressed: Bool = false) -> ExpandCollapseAction {
        guard let eventType = eventType else { return .toggle }
        switch eventType {
        case .leftMouseDown, .leftMouseDragged, .rightMouseDown, .rightMouseDragged: return .ignore
        default: break
        }
        if optionPressed { return .toggleSeparators }
        switch eventType {
        case .leftMouseUp: return shiftPressed ? .toggleWithFullBar : .toggle
        case .rightMouseUp: return .contextMenu
        default: return .toggleSeparators
        }
    }
}
