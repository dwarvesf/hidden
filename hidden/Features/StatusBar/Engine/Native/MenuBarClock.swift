//
//  MenuBarClock.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import AppKit
import ApplicationServices

// The menu-bar clock, which opens Notification Center. While any app holds a
// macOS 27 menu-bar visibility restriction, MenuBarAgent ignores the clock, mouse
// clicks and AXPress alike: the restriction is assessment (exam) mode, which keeps
// notifications out of reach (#410). The native engine therefore watches for
// clicks on the clock and presses it itself with the restriction lifted.
protocol MenuBarClockProviding: AnyObject {
    // Runs on the main queue with the location of a left click on the clock made
    // while Notification Center was closed. Nothing is watched while nil.
    var onClick: ((CGPoint) -> Void)? { get set }

    // Presses the clock at that location. The completion runs on the main queue
    // once macOS has handled the press.
    func press(at location: CGPoint, completion: @escaping () -> Void)
}

// Finds the clock through public Accessibility API: MenuBarAgent's menu extra
// `com.apple.menuextra.clock`, which has an AXPress action. Locations are global
// display coordinates with a top-left origin, as CGEvent and Accessibility use.
final class SystemMenuBarClock: MenuBarClockProviding {
    private static let ownerBundleIdentifier = "com.apple.MenuBarAgent"
    private static let clockIdentifier = "com.apple.menuextra.clock"
    private static let notificationCenterBundleIdentifier = "com.apple.notificationcenterui"
    // Well above how long MenuBarAgent takes to answer right after a lift.
    private static let messagingTimeout: Float = 0.5

    // MenuBarAgent ignores a press that reaches it before it has applied a lifted
    // restriction, and answers Accessibility only once it has (40-90ms on 27.0.1).
    // Looking the clock up after this pause therefore holds the press back until
    // then; looking it up straight away sometimes beat the lift and was ignored.
    private static let liftDelay: TimeInterval = 0.03

    var onClick: ((CGPoint) -> Void)? {
        didSet { updateMonitor() }
    }

    private var monitor: Any?
    // The clock's frame when a click on it began with Notification Center closed.
    private var clickedClockFrame: CGRect?

    deinit {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    func press(at location: CGPoint, completion: @escaping () -> Void) {
        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + Self.liftDelay) {
            let clocks = Self.clocks()
            if let clock = clocks.first(where: { $0.frame.contains(location) }) ?? clocks.first {
                AXUIElementPerformAction(clock.element, kAXPressAction as CFString)
            }
            DispatchQueue.main.async(execute: completion)
        }
    }

    private func updateMonitor() {
        if onClick != nil, monitor == nil {
            monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
                self?.handle(event)
            }
        } else if onClick == nil, let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
            clickedClockFrame = nil
        }
    }

    // Notification Center is checked when the click begins: a click on the clock
    // closes an open panel by itself, restricted or not, and pressing the clock as
    // well would reopen it. The press waits for the click to end.
    private func handle(_ event: NSEvent) {
        guard let location = event.cgEvent?.location else { return }
        switch event.type {
        case .leftMouseDown:
            // ⌘-drag rearranges the bar and ⌃-click is a right click.
            guard event.modifierFlags.isDisjoint(with: [.command, .control]),
                  Self.isInMenuBar(location),
                  let clock = Self.clocks().first(where: { $0.frame.contains(location) }),
                  !Self.isNotificationCenterOpen else {
                clickedClockFrame = nil
                return
            }
            clickedClockFrame = clock.frame
        case .leftMouseUp:
            defer { clickedClockFrame = nil }
            if clickedClockFrame?.contains(location) == true {
                onClick?(location)
            }
        default:
            break
        }
    }

    // Keeps the Accessibility lookups to clicks in a menu bar.
    private static func isInMenuBar(_ location: CGPoint) -> Bool {
        guard let primaryHeight = NSScreen.screens.first?.frame.maxY else { return false }
        return NSScreen.screens.contains { screen in
            let top = primaryHeight - screen.frame.maxY
            let height = max(screen.frame.maxY - screen.visibleFrame.maxY, screen.safeAreaInsets.top, NSStatusBar.system.thickness)
            return location.x >= screen.frame.minX && location.x <= screen.frame.maxX
                && location.y >= top && location.y <= top + height
        }
    }

    // Each item sits in a hosting group: bar > group > menu extra.
    private static func clocks() -> [(element: AXUIElement, frame: CGRect)] {
        guard let agent = NSRunningApplication.runningApplications(withBundleIdentifier: ownerBundleIdentifier).first else { return [] }
        let app = AXUIElementCreateApplication(agent.processIdentifier)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        guard let bar = value(of: app, "AXExtrasMenuBar") else { return [] }
        var clocks: [(element: AXUIElement, frame: CGRect)] = []
        for group in children(of: bar as! AXUIElement) {
            for item in [group] + children(of: group)
            where value(of: item, "AXIdentifier") as? String == clockIdentifier {
                if let frame = AccessibilityMenuBarInventory.frame(of: item) {
                    clocks.append((item, frame))
                }
            }
        }
        return clocks
    }

    // The panel is a window as tall as the screen; banners are a few rows tall and
    // desktop widgets sit below the desktop. Owner, layer and bounds need no
    // Screen Recording permission, unlike window names.
    private static var isNotificationCenterOpen: Bool {
        let owners = Set(NSRunningApplication.runningApplications(withBundleIdentifier: notificationCenterBundleIdentifier).map(\.processIdentifier))
        guard !owners.isEmpty,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        let minimumHeight = (NSScreen.screens.map(\.frame.height).min() ?? 0) / 2
        return windows.contains { window in
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t, owners.contains(pid),
                  let layer = window[kCGWindowLayer as String] as? Int, layer >= 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else { return false }
            return frame.height >= minimumHeight
        }
    }

    private static func value(of element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        return value(of: element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }
}
