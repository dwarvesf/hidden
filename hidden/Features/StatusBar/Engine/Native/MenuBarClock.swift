//
//  MenuBarClock.swift
//  Hidden Bar
//
//  Copyright © 2026 Console Labs. All rights reserved.
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

    // Presses the clock at that location. `restore` runs once on the main queue
    // when a lifted restriction may come back: right after the press for
    // `.restoreAfterPress`, once the panel shows for `.restoreWhenPanelShows`.
    // `finished` runs once on the main queue after it.
    func press(at location: CGPoint, mode: ClockPressMode,
               restore: @escaping () -> Void, finished: @escaping (ClockPressOutcome) -> Void)

    // Whether the Notification Center panel is on screen (one window-list read, and
    // an Accessibility read while one of its windows is up).
    var isNotificationCenterOpen: Bool { get }
}

// A click on the clock while the bar is collapsed: expand the bar as a click on
// the arrow does, replay the click so Notification Center opens, and collapse
// again once the panel closes. Only a bar this expanded is collapsed, and only
// while the user has not expanded or collapsed it since. Main queue; `now`,
// `after` and `panelIsOpen` are injectable for tests.
final class NotificationCenterSession {
    struct Timing: Equatable {
        // How often an open panel is checked; each check is one window-list read.
        var pollInterval: TimeInterval = 0.1
        // Stop watching after this long and leave the bar as it is.
        var cap: TimeInterval = 600
        // How long a replay may wait for an activation in flight to land.
        var busyTimeout: TimeInterval = 1
    }

    private enum Phase {
        case idle, pressing, open
    }

    private let timing: Timing
    private let now: () -> TimeInterval
    private let after: (TimeInterval, @escaping () -> Void) -> Void
    private let panelIsOpen: () -> Bool
    // Replays the click; false when it cannot start yet.
    private let press: (CGPoint, ClockPressMode, @escaping (ClockPressOutcome) -> Void) -> Bool
    private let expand: () -> Void
    private let collapse: () -> Void

    private var phase = Phase.idle
    private var session = 0
    private var startedAt: TimeInterval = 0
    // Hidden Bar expanded the bar for this click, and the user has not toggled it since.
    private(set) var expandedBar = false

    init(timing: Timing = Timing(),
         now: @escaping () -> TimeInterval,
         after: @escaping (TimeInterval, @escaping () -> Void) -> Void,
         panelIsOpen: @escaping () -> Bool,
         press: @escaping (CGPoint, ClockPressMode, @escaping (ClockPressOutcome) -> Void) -> Bool,
         expand: @escaping () -> Void,
         collapse: @escaping () -> Void) {
        self.timing = timing
        self.now = now
        self.after = after
        self.panelIsOpen = panelIsOpen
        self.press = press
        self.expand = expand
        self.collapse = collapse
    }

    // From the click until the panel closed or the cap passed. Auto-collapse waits meanwhile.
    var isActive: Bool {
        return phase != .idle
    }

    func clockClicked(at location: CGPoint, barCollapsed: Bool) {
        // A click just after the panel closed, before the check noticed, keeps the claim.
        expandedBar = barCollapsed || (isActive && expandedBar)
        session += 1
        phase = .pressing
        startedAt = now()
        #if DEBUG
        ClockFlashTimeline.reset()
        ClockFlashTimeline.mark(barCollapsed ? "clockClickedCollapsed" : "clockClickedExpanded")
        #endif
        if barCollapsed {
            expand()
        }
        replay(at: location, mode: .restoreAfterPress, session: session)
    }

    // The user expanded or collapsed the bar: it stays as they left it.
    func userChangedBar() {
        expandedBar = false
    }

    private func replay(at location: CGPoint, mode: ClockPressMode, session: Int) {
        guard session == self.session, phase == .pressing else { return }
        let started = press(location, mode) { [weak self] outcome in
            self?.pressed(outcome, at: location, mode: mode, session: session)
        }
        guard !started else { return }
        guard now() - startedAt < timing.busyTimeout else { return end(collapsing: true, "busy") }
        after(timing.pollInterval) { [weak self] in
            self?.replay(at: location, mode: mode, session: session)
        }
    }

    private func pressed(_ outcome: ClockPressOutcome, at location: CGPoint, mode: ClockPressMode, session: Int) {
        guard session == self.session, phase == .pressing else { return }
        switch outcome {
        case .panelShown:
            phase = .open
            poll(session)
        case .noPanel where mode == .restoreAfterPress:
            NSLog("NativeVisibility: the clock press opened nothing; pressing once more")
            replay(at: location, mode: .restoreWhenPanelShows, session: session)
        case .noPanel, .noClock:
            // Nothing opened: put back what the click changed.
            end(collapsing: true, "noPanel")
        }
    }

    private func poll(_ session: Int) {
        guard session == self.session, phase == .open else { return }
        if !panelIsOpen() {
            return end(collapsing: true, "panelClosed")
        }
        if now() - startedAt >= timing.cap {
            return end(collapsing: false, "cap")
        }
        after(timing.pollInterval) { [weak self] in
            self?.poll(session)
        }
    }

    private func end(collapsing: Bool, _ reason: String) {
        let collapses = collapsing && expandedBar
        phase = .idle
        expandedBar = false
        #if DEBUG
        ClockFlashTimeline.mark(collapses ? "\(reason)Collapsing" : "\(reason)LeftAsIs")
        NSLog("NativeVisibility: clock timeline \(ClockFlashTimeline.summary)")
        #endif
        if collapses {
            collapse()
        }
    }
}

enum ClockPressMode: Equatable {
    // Measured on 27.2: the panel opens and stays open when the restriction is
    // back a moment after MenuBarAgent took the press, so hidden icons show only
    // for that moment.
    case restoreAfterPress
    // The fallback when that press opened nothing: hold the lift until the panel
    // shows or the timeout passes.
    case restoreWhenPanelShows
}

enum ClockPressOutcome: Equatable {
    case panelShown
    case noPanel
    case noClock
}

// When to bring the restriction back around one replayed press, and when to
// stop waiting for the panel. Times are seconds since the press was posted.
// Runs on one serial queue; `now` and `after` are injectable for tests.
final class ClockReplay {
    struct Timing: Equatable {
        // How long MenuBarAgent gets to take the press before the restriction is
        // back. Zero for a synchronous press (AXPress returns once it is handled).
        var restoreAfterPress: TimeInterval
        var panelTimeout: TimeInterval = 0.3
        // A window-list read costs about 1 ms without .excludeDesktopElements.
        var pollInterval: TimeInterval = 0.005
    }

    private let timing: Timing
    private let mode: ClockPressMode
    private let now: () -> TimeInterval
    private let after: (TimeInterval, @escaping () -> Void) -> Void
    private let panelIsOpen: () -> Bool
    private let restore: () -> Void
    private let finished: (ClockPressOutcome) -> Void
    private var pressedAt: TimeInterval = 0
    private var restored = false
    private var done = false

    init(timing: Timing, mode: ClockPressMode,
         now: @escaping () -> TimeInterval,
         after: @escaping (TimeInterval, @escaping () -> Void) -> Void,
         panelIsOpen: @escaping () -> Bool,
         restore: @escaping () -> Void,
         finished: @escaping (ClockPressOutcome) -> Void) {
        self.timing = timing
        self.mode = mode
        self.now = now
        self.after = after
        self.panelIsOpen = panelIsOpen
        self.restore = restore
        self.finished = finished
    }

    // Call right after the press is posted.
    func pressed() {
        pressedAt = now()
        tick()
    }

    private func tick() {
        guard !done else { return }
        let elapsed = now() - pressedAt
        if mode == .restoreAfterPress, elapsed >= timing.restoreAfterPress {
            restoreOnce()
        }
        if panelIsOpen() {
            return finish(.panelShown)
        }
        if elapsed >= timing.panelTimeout {
            return finish(.noPanel)
        }
        var wait = min(timing.pollInterval, timing.panelTimeout - elapsed)
        if mode == .restoreAfterPress, !restored {
            wait = min(wait, timing.restoreAfterPress - elapsed)
        }
        // At least 1 ms, so float rounding can never schedule a step at the same instant.
        after(max(wait, 0.001)) { [self] in tick() }
    }

    private func restoreOnce() {
        guard !restored else { return }
        restored = true
        #if DEBUG
        ClockFlashTimeline.mark("restoreDue")
        #endif
        restore()
    }

    private func finish(_ outcome: ClockPressOutcome) {
        restoreOnce()
        done = true
        #if DEBUG
        ClockFlashTimeline.mark(outcome == .panelShown ? "panelAppeared" : "panelTimeout")
        #endif
        finished(outcome)
    }
}

// Whether Notification Center's panel is open. A notification on screen keeps a
// window up that the window list cannot tell from the panel: same owner, layer and
// screen-tall bounds (27.0.1). One left on screen when the bar collapses stays
// there, and taking it for the panel dropped every click on the clock (the click
// was not replayed, or the replay reported the panel shown without pressing).
// `identifiers` lists the AXIdentifiers in Notification Center's windows, nil when
// Accessibility cannot read them; it is asked only while a window is up.
enum NotificationCenterPanel {
    // Only the panel shows Edit Widgets; a notification on its own never does.
    static let panelControlIdentifier = "widget-editor-button"

    static func isOpen(windowUp: Bool, identifiers: () -> [String]?) -> Bool {
        guard windowUp else { return false }
        guard let identifiers = identifiers() else { return true }
        return identifiers.contains(panelControlIdentifier)
    }
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

    // AXPress opens and immediately closes the panel on macOS 27.2 (with or without
    // a restriction), so a mouse click is replayed instead. The engine removes our
    // monitor before calling here.
    // MenuBarAgent takes a posted click within a few ms; this leaves room to spare.
    private static let hidRestoreAfterPress: TimeInterval = 0.04

    func press(at location: CGPoint, mode: ClockPressMode,
               restore: @escaping () -> Void, finished: @escaping (ClockPressOutcome) -> Void) {
        // NSScreen must be read on the main thread, before the background AX walk.
        let minimumPanelHeight = (NSScreen.screens.map(\.frame.height).min() ?? 0) / 2
        let queue = DispatchQueue.global(qos: .userInteractive)
        let onMain = { (outcome: ClockPressOutcome) in
            DispatchQueue.main.async { restore(); finished(outcome) }
        }
        queue.asyncAfter(deadline: .now() + Self.liftDelay) {
            let clocks = Self.clocks()
            // Never replay on a different display if its clock cannot be found.
            guard let clock = clocks.first(where: { $0.frame.contains(location) }),
                  let events = Self.clickEvents(at: CGPoint(x: clock.frame.midX, y: clock.frame.midY)) else {
                return onMain(.noClock)
            }
            #if DEBUG
            ClockFlashTimeline.mark("liftEffective")
            #endif
            // A panel that opened late from the first press must not be closed again.
            if Self.notificationCenterIsOpen(minimumHeight: minimumPanelHeight) {
                return onMain(.panelShown)
            }
            var restoreAfterPress = Self.hidRestoreAfterPress
            #if DEBUG
            if Self.debugPressWithAX {
                AXUIElementPerformAction(clock.element, kAXPressAction as CFString)
                restoreAfterPress = 0
            } else if let pid = Self.debugPostToPid {
                events.forEach { $0.postToPid(pid) }
            } else {
                events.forEach { $0.post(tap: .cghidEventTap) }
            }
            ClockFlashTimeline.mark("replayPosted")
            #else
            events.forEach { $0.post(tap: .cghidEventTap) }
            #endif
            let replay = ClockReplay(timing: .init(restoreAfterPress: restoreAfterPress), mode: mode,
                                     now: { ProcessInfo.processInfo.systemUptime },
                                     after: { queue.asyncAfter(deadline: .now() + $0, execute: $1) },
                                     panelIsOpen: { Self.notificationCenterIsOpen(minimumHeight: minimumPanelHeight) },
                                     restore: { DispatchQueue.main.async(execute: restore) },
                                     finished: { outcome in DispatchQueue.main.async { finished(outcome) } })
            replay.pressed()
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

    var isNotificationCenterOpen: Bool {
        return Self.isNotificationCenterOpen
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
              // .excludeDesktopElements costs about 5 ms more per read; layer >= 0
              // already leaves the desktop out.
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return false }
        let windowUp = windows.contains { window in
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t, owners.contains(pid),
                  let layer = window[kCGWindowLayer as String] as? Int, layer >= 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else { return false }
            return frame.height >= minimumHeight
        }
        return NotificationCenterPanel.isOpen(windowUp: windowUp, identifiers: { identifiers(in: owners) })
    }

    // The AXIdentifiers in Notification Center's windows, nil when Accessibility cannot read them.
    private static func identifiers(in owners: Set<pid_t>) -> [String]? {
        var found: [String] = []
        for pid in owners {
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, messagingTimeout)
            guard let windows = value(of: app, kAXWindowsAttribute) as? [AXUIElement] else { return nil }
            for window in windows {
                collectIdentifiers(of: window, depth: 0, into: &found)
            }
        }
        return found
    }

    // The panel's controls sit four levels below its window; deeper levels hold notification text.
    private static func collectIdentifiers(of element: AXUIElement, depth: Int, into found: inout [String]) {
        if let identifier = value(of: element, "AXIdentifier") as? String {
            found.append(identifier)
        }
        guard depth < 5 else { return }
        for child in children(of: element) {
            collectIdentifiers(of: child, depth: depth + 1, into: &found)
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
