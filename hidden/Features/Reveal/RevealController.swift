//
//  RevealController.swift
//  Hidden Bar
//
//  Copyright © 2026 Console Labs. All rights reserved.
//

import AppKit

/// How the controller adds and removes global event monitors; tests swap it.
protocol RevealEventMonitoring {
    func addGlobalMonitor(matching mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> Void) -> Any?
    func removeMonitor(_ token: Any)
}

struct SystemRevealEventMonitoring: RevealEventMonitoring {
    func addGlobalMonitor(matching mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> Void) -> Any? {
        NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler)
    }

    func removeMonitor(_ token: Any) {
        NSEvent.removeMonitor(token)
    }
}

extension ScreenBand {
    /// Every attached screen's strip, with the camera housing where there is one.
    static func live() -> [ScreenBand] {
        NSScreen.screens.map { screen in
            var gap: ClosedRange<CGFloat>?
            if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea, left.maxX <= right.minX {
                gap = left.maxX...right.minX
            }
            return ScreenBand(frame: screen.frame, visibleFrame: screen.visibleFrame, notchGap: gap)
        }
    }
}

/// What the controller asks of the status bar controller.
struct RevealHost {
    var isCollapsed: () -> Bool
    /// Hidden Bar's own menu is open, so a gesture must not pull the bar away.
    var isOwnMenuOpen: () -> Bool
    var show: () -> Void
    /// Scroll up: collapse now.
    var hide: () -> Void
    /// A click off the menu bar: collapse through the auto-collapse path, which
    /// waits while Preferences or a popup is open.
    var hideOffMenuBar: () -> Void
}

/// Shows the hidden icons for a scroll, a click on empty menu bar space or a
/// pointer shake, each opt-in. Monitors exist only while their pref is on, and
/// are global mouse and scroll monitors only: no key monitor, no new permission.
final class RevealController {
    private let host: RevealHost
    private let isEnabled: (RevealTrigger) -> Bool
    /// True while presentation mode is on: a gesture must not pull the hidden
    /// icons out in front of the room, so every gesture does nothing.
    private let isSuspended: () -> Bool
    private let screens: () -> [ScreenBand]
    private let monitoring: RevealEventMonitoring
    private let canHitTest: () -> Bool
    private let hitTest: (CGPoint, @escaping (HitTarget) -> Void) -> Void

    private var scrollMonitor: Any?
    private var moveMonitor: Any?
    private var mouseDownMonitor: Any?
    private var scrollDetector = ScrollRevealDetector()
    private var shakeDetector = ShakeDetector()

    /// Set while the icons shown by a gesture are still out; a click off the
    /// menu bar hides them only then, so the arrow's own behaviour is untouched.
    private(set) var revealedByGesture = false
    /// How often each gesture fired, so Debug builds can tune the thresholds.
    private(set) var triggerCounts: [RevealTrigger: Int] = [:]
    /// Debug hooks and tests stand in for the Accessibility read.
    var hitTargetOverride: HitTarget?

    init(host: RevealHost,
         isEnabled: @escaping (RevealTrigger) -> Bool,
         isSuspended: @escaping () -> Bool = { false },
         screens: @escaping () -> [ScreenBand],
         monitoring: RevealEventMonitoring = SystemRevealEventMonitoring(),
         canHitTest: @escaping () -> Bool = RevealHitTester.isAvailable,
         hitTest: @escaping (CGPoint, @escaping (HitTarget) -> Void) -> Void = RevealHitTester.resolve) {
        self.host = host
        self.isEnabled = isEnabled
        self.isSuspended = isSuspended
        self.screens = screens
        self.monitoring = monitoring
        self.canHitTest = canHitTest
        self.hitTest = hitTest
    }

    deinit {
        [scrollMonitor, moveMonitor, mouseDownMonitor].compactMap { $0 }.forEach(monitoring.removeMonitor)
    }

    // MARK: monitors

    /// Installs or removes each monitor to match the prefs. The mouse-down
    /// monitor also lives while a gesture's icons are out, to hide them again.
    func sync() {
        update(&scrollMonitor, wanted: isEnabled(.scroll), mask: .scrollWheel) { [weak self] event in
            self?.ingestScroll(deltaY: Self.contentDeltaY(of: event), time: event.timestamp,
                               isMomentum: event.momentumPhase != [], at: NSEvent.mouseLocation)
        }
        update(&moveMonitor, wanted: isEnabled(.shake), mask: .mouseMoved) { [weak self] event in
            self?.ingestMouseMoved(at: NSEvent.mouseLocation, time: event.timestamp)
        }
        update(&mouseDownMonitor, wanted: isEnabled(.click) || revealedByGesture, mask: .leftMouseDown) { [weak self] _ in
            self?.ingestMouseDown(at: NSEvent.mouseLocation)
        }
        if !isEnabled(.scroll) { scrollDetector.reset() }
        if !isEnabled(.shake) { shakeDetector.reset() }
    }

    private func update(_ monitor: inout Any?, wanted: Bool, mask: NSEvent.EventTypeMask,
                        handler: @escaping (NSEvent) -> Void) {
        if wanted, monitor == nil {
            monitor = monitoring.addGlobalMonitor(matching: mask, handler: handler)
        } else if !wanted, let existing = monitor {
            monitoring.removeMonitor(existing)
            monitor = nil
        }
    }

    private static func contentDeltaY(of event: NSEvent) -> CGFloat {
        event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * RevealTuning.scrollLineHeight
    }

    // MARK: events

    func ingestScroll(deltaY: CGFloat, time: TimeInterval, isMomentum: Bool, at point: CGPoint) {
        guard isEnabled(.scroll), !isSuspended() else { return }
        guard MenuBarBand.contains(point, in: screens()) else {
            scrollDetector.reset()
            return
        }
        guard let action = scrollDetector.feed(deltaY: deltaY, at: time, isMomentum: isMomentum) else { return }
        resolveTarget(at: point) { [weak self] target in
            guard let self = self else { return }
            switch action {
            case .show:
                self.revealIfAllowed(.scroll, target: target)
            case .hide:
                guard RevealPolicy.allowsScrollHide(target: target, barIsCollapsed: self.host.isCollapsed(),
                                                    ownMenuIsOpen: self.host.isOwnMenuOpen()) else { return }
                self.host.hide()
            }
        }
    }

    func ingestMouseMoved(at point: CGPoint, time: TimeInterval) {
        guard isEnabled(.shake), !isSuspended() else { return }
        let inBand = MenuBarBand.contains(point, in: screens())
        guard shakeDetector.feed(x: point.x, at: time, inBand: inBand) else { return }
        revealIfAllowed(.shake, target: .unknown)
    }

    func ingestMouseDown(at point: CGPoint) {
        let inBand = MenuBarBand.contains(point, in: screens())
        if inBand {
            guard isEnabled(.click), !isSuspended(), !MenuBarBand.isInNotch(point, in: screens()) else { return }
            resolveTarget(at: point) { [weak self] target in
                self?.revealIfAllowed(.click, target: target)
            }
            return
        }
        if host.isCollapsed() {
            gestureRevealEnded()
            return
        }
        if RevealPolicy.allowsOffBarHide(clickIsInMenuBar: false, revealedByGesture: revealedByGesture,
                                         barIsCollapsed: false, ownMenuIsOpen: host.isOwnMenuOpen()) {
            host.hideOffMenuBar()
        }
    }

    /// The bar collapsed, by any route.
    func barDidCollapse() {
        gestureRevealEnded()
    }

    // MARK: private

    private func revealIfAllowed(_ trigger: RevealTrigger, target: HitTarget) {
        guard RevealPolicy.allowsShow(trigger, target: target, barIsCollapsed: host.isCollapsed(),
                                      ownMenuIsOpen: host.isOwnMenuOpen()) else { return }
        triggerCounts[trigger, default: 0] += 1
        revealedByGesture = true
        host.show()
        sync()
    }

    private func gestureRevealEnded() {
        guard revealedByGesture else { return }
        revealedByGesture = false
        sync()
    }

    private func resolveTarget(at point: CGPoint, completion: @escaping (HitTarget) -> Void) {
        if let forced = hitTargetOverride {
            completion(forced)
            return
        }
        guard canHitTest() else {
            completion(.unknown)
            return
        }
        hitTest(point, completion)
    }
}

#if DEBUG
extension RevealController {
    /// What the `reveal-sim` debug command runs: the same ingest calls a real
    /// event makes, at a point in the first menu bar strip, with the
    /// Accessibility read replaced by "empty space". Prefs still gate it.
    func simulate(_ gesture: String, now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard let rect = screens().compactMap({ $0.rect }).first else {
            return NSLog("DebugHooks: reveal-sim has no menu bar strip (full-screen app?)")
        }
        let point = CGPoint(x: rect.minX + 120, y: rect.midY)
        let previousOverride = hitTargetOverride
        hitTargetOverride = .emptySpace
        defer { hitTargetOverride = previousOverride }
        switch gesture {
        case "scroll", "scroll-down":
            ingestScroll(deltaY: -RevealTuning.scrollThreshold * 2, time: now, isMomentum: false, at: point)
        case "scroll-up":
            ingestScroll(deltaY: RevealTuning.scrollThreshold * 2, time: now, isMomentum: false, at: point)
        case "click":
            ingestMouseDown(at: point)
        case "shake":
            let swing = RevealTuning.shakeMinSwing * 2
            let step = RevealTuning.shakeWindow / Double(RevealTuning.shakeReversals + 3)
            for index in 0...(RevealTuning.shakeReversals + 1) {
                let x = point.x + (index % 2 == 0 ? 0 : swing)
                ingestMouseMoved(at: CGPoint(x: x, y: point.y), time: now + step * Double(index))
            }
        default:
            NSLog("DebugHooks: reveal-sim unknown gesture \(gesture)")
        }
    }

    var debugState: [String: Any] {
        ["revealedByGesture": revealedByGesture,
         "revealTriggerCounts": Dictionary(uniqueKeysWithValues: RevealTrigger.allCases.map { ($0.rawValue, triggerCounts[$0] ?? 0) })]
    }
}
#endif
