//
//  ExpandCollapseAction.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import AppKit

// What a press on the expand/collapse button should do. Kept as a pure mapping
// so the decision is unit-testable without a live status item or a real NSEvent.
enum ExpandCollapseAction {
    case toggle
    case contextMenu
    case toggleSeparators
    case toggleWithFullBar
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
        if optionPressed { return .toggleSeparators }
        switch eventType {
        case .leftMouseUp: return shiftPressed ? .toggleWithFullBar : .toggle
        case .rightMouseUp: return .contextMenu
        default: return .toggleSeparators
        }
    }
}

// Switching to .regular and activating in the same runloop turn does not make the
// app active on macOS 14+, where activation is a cooperative request and
// activate(ignoringOtherApps:) is deprecated and ignored. The full menu bar needs
// Hidden Bar frontmost, so the request goes out on the next turn, after the policy
// change has registered, and is dropped if the bar collapsed in the meantime.
enum FullBarActivation {
    enum Request: Equatable {
        case cooperative
        case legacy
    }

    static func request(isMacOS14OrLater: Bool) -> Request {
        return isMacOS14OrLater ? .cooperative : .legacy
    }

    static func switchToRegularAndActivate(
        isMacOS14OrLater: Bool = ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 14, minorVersion: 0, patchVersion: 0)),
        setPolicy: (NSApplication.ActivationPolicy) -> Void = { _ = NSApp.setActivationPolicy($0) },
        deferToNextTurn: (@escaping () -> Void) -> Void = { DispatchQueue.main.async(execute: $0) },
        stillWanted: @escaping () -> Bool,
        activate: @escaping (Request) -> Void = FullBarActivation.perform
    ) {
        setPolicy(.regular)
        let request = request(isMacOS14OrLater: isMacOS14OrLater)
        deferToNextTurn {
            guard stillWanted() else { return }
            activate(request)
        }
    }

    static func perform(_ request: Request) {
        switch request {
        case .cooperative:
            if #available(macOS 14.0, *) {
                NSApp.activate()
            }
        case .legacy:
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
