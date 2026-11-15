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

    #if DEBUG
    // Test hook: post the replayed press to this process only, never the HID stream.
    static var debugPostToPid: pid_t?
    // Test hook: replay with AXPress instead, which opens the panel without any
    // pointer input (on 27.2 it closes again by itself a few hundred ms later).
    static var debugPressWithAX = false
    #endif

    private var monitor: Any?
    // The clock's frame when a click on it began with Notification Center closed.
    private var clickedClockFrame: CGRect?

    deinit {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // AXPress opens and immediately closes the panel on macOS 27.2. Replay a
    // mouse click instead, and restore hiding only after the panel appears (or
    // a bounded timeout). The engine removes our monitor before calling here.
    private static let openTimeout: TimeInterval = 0.5
    private static let pollInterval: TimeInterval = 0.02

    func press(at location: CGPoint, completion: @escaping () -> Void) {
        // NSScreen must be read on the main thread, before the background AX walk.
        let minimumPanelHeight = (NSScreen.screens.map(\.frame.height).min() ?? 0) / 2
        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + Self.liftDelay) {
            let clocks = Self.clocks()
            // Never replay on a different display if its clock cannot be found.
            guard let clock = clocks.first(where: { $0.frame.contains(location) }),
                  let events = Self.clickEvents(at: CGPoint(x: clock.frame.midX, y: clock.frame.midY)) else {
                return DispatchQueue.main.async(execute: completion)
            }
            #if DEBUG
            ClockFlashTimeline.mark("liftEffective")
            if Self.debugPressWithAX {
                AXUIElementPerformAction(clock.element, kAXPressAction as CFString)
                ClockFlashTimeline.mark("replayPosted")
                return Self.waitForPanel(until: ProcessInfo.processInfo.systemUptime + Self.openTimeout,
                                         minimumHeight: minimumPanelHeight, completion: completion)
            }
            if let pid = Self.debugPostToPid {
                events.forEach { $0.postToPid(pid) }
                ClockFlashTimeline.mark("replayPosted")
                return Self.waitForPanel(until: ProcessInfo.processInfo.systemUptime + Self.openTimeout,
                                         minimumHeight: minimumPanelHeight, completion: completion)
            }
            #endif
            events.forEach { $0.post(tap: .cghidEventTap) }
            #if DEBUG
            ClockFlashTimeline.mark("replayPosted")
            #endif
            Self.waitForPanel(until: ProcessInfo.processInfo.systemUptime + Self.openTimeout,
                              minimumHeight: minimumPanelHeight, completion: completion)
        }
    }

    static func clickEvents(at point: CGPoint) -> [CGEvent]? {
        // Build both before posting either, so allocation failure cannot leave a
        // mouse-down without its matching mouse-up. Do not inherit modifiers.
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
                                 mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                               mouseCursorPosition: point, mouseButton: .left) else { return nil }
        for event in [down, up] {
            event.flags = []
            event.setIntegerValueField(.mouseEventClickState, value: 1)
        }
        return [down, up]
    }

    private static func waitForPanel(until deadline: TimeInterval, minimumHeight: CGFloat,
                                     completion: @escaping () -> Void) {
        let isOpen = notificationCenterIsOpen(minimumHeight: minimumHeight)
        if isOpen || ProcessInfo.processInfo.systemUptime >= deadline {
            #if DEBUG
            ClockFlashTimeline.mark(isOpen ? "panelAppeared" : "panelTimeout")
            #endif
            return DispatchQueue.main.async(execute: completion)
        }
        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + pollInterval) {
            waitForPanel(until: deadline, minimumHeight: minimumHeight, completion: completion)
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
        return notificationCenterIsOpen(minimumHeight: (NSScreen.screens.map(\.frame.height).min() ?? 0) / 2)
    }

    private static func notificationCenterIsOpen(minimumHeight: CGFloat) -> Bool {
        let owners = Set(NSRunningApplication.runningApplications(withBundleIdentifier: notificationCenterBundleIdentifier).map(\.processIdentifier))
        guard !owners.isEmpty,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
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

#if DEBUG
// When each step of the last clock replay happened (systemUptime, seconds), for
// measuring how long hidden icons show. Debug builds only.
enum ClockFlashTimeline {
    private static let lock = NSLock()
    private static var marks: [(name: String, time: TimeInterval)] = []

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        marks = []
    }

    static func mark(_ name: String) {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock(); defer { lock.unlock() }
        marks.append((name, now))
    }

    static var snapshot: [[String: Any]] {
        lock.lock(); defer { lock.unlock() }
        return marks.map { ["step": $0.name, "uptime": $0.time] }
    }

    static var summary: String {
        lock.lock(); defer { lock.unlock() }
        guard let start = marks.first?.time else { return "empty" }
        return marks.map { String(format: "%@ +%.1fms", $0.name, ($0.time - start) * 1000) }.joined(separator: ", ")
    }
}
#endif
