//
//  PaletteRevealSession.swift
//  Hidden Bar
//
//  Copyright © 2026 Console Labs. All rights reserved.
//

import Foundation

/// How a palette open ended, as the palette needs to tell the user.
enum PaletteOpenResult: Equatable {
    /// The icon was pressed; its own menu or panel is up.
    case opened
    /// The app's icon was not in the menu bar after it was allowed.
    case noItem
    /// The icon is there but does not take an Accessibility press.
    case noPress
    /// The engine cannot lift the restriction for one app.
    case unavailable
    /// Presentation mode keeps this app hidden on purpose.
    case sensitive
}

/// What the engine did when asked to allow one app.
enum PaletteLift: Equatable {
    /// The restriction was changed and must be put back.
    case lifted
    /// The app is shown already (the bar is expanded, or nothing is hidden).
    case alreadyShown
    case unavailable
    /// The app is on the presentation mode's sensitive list while it is on.
    case sensitive
}

enum PalettePressOutcome: Equatable {
    case pressed
    /// No icon of the app is in the menu bar yet.
    case noItem
    case noPress
}

/// Opens one hidden app's own menu: allow that app, press its icon, watch until
/// its menu or panel is gone, then put the restriction back. The clock session
/// (NotificationCenterSession) does the same for the clock. A bar the user
/// expanded or collapsed meanwhile stays as they left it. Main queue; every
/// system read is a closure, so tests run it with fake time.
final class PaletteRevealSession {
    struct Timing: Equatable {
        /// How often an open menu is checked.
        var pollInterval: TimeInterval = 0.1
        /// macOS applies a lifted restriction a moment after it is asked; the
        /// icon is looked up after this pause.
        var liftSettle: TimeInterval = 0.05
        /// How long to look for the icon once it is allowed.
        var itemTimeout: TimeInterval = 1
        /// An app that opens a panel, not a menu, gives no menu; after this wait
        /// the session follows the app's focus instead.
        var menuAppearTimeout: TimeInterval = 0.8
        /// How long a panel that never took focus is waited for.
        var panelGrace: TimeInterval = 2
        /// A panel's longest stay.
        var panelCap: TimeInterval = 15
        /// A menu's longest stay.
        var menuCap: TimeInterval = 600
        /// The engine must answer an allow within this.
        var liftCap: TimeInterval = 5
    }

    private enum Phase {
        case idle, lifting, pressing, watching
    }

    private let timing: Timing
    private let now: () -> TimeInterval
    private let after: (TimeInterval, @escaping () -> Void) -> Void
    private let allow: (String, @escaping (PaletteLift) -> Void) -> Void
    private let press: (String, @escaping (PalettePressOutcome) -> Void) -> Void
    private let menuIsOpen: (String) -> Bool
    private let appIsActive: (String) -> Bool
    private let restore: () -> Void

    private var phase = Phase.idle
    private var session = 0
    private var bundle = ""
    private var startedAt: TimeInterval = 0
    private var liftedAt: TimeInterval = 0
    private var pressedAt: TimeInterval = 0
    // Hidden Bar changed the restriction for this open, and the user has not
    // expanded or collapsed the bar since.
    private(set) var liftedRestriction = false
    private var menuSeen = false
    private var activeSeen = false
    private var completion: ((PaletteOpenResult) -> Void)?
    /// Why the last open ended, for the debug state and tests.
    private(set) var lastEndReason: String?

    init(timing: Timing = Timing(),
         now: @escaping () -> TimeInterval,
         after: @escaping (TimeInterval, @escaping () -> Void) -> Void,
         allow: @escaping (String, @escaping (PaletteLift) -> Void) -> Void,
         press: @escaping (String, @escaping (PalettePressOutcome) -> Void) -> Void,
         menuIsOpen: @escaping (String) -> Bool,
         appIsActive: @escaping (String) -> Bool,
         restore: @escaping () -> Void) {
        self.timing = timing
        self.now = now
        self.after = after
        self.allow = allow
        self.press = press
        self.menuIsOpen = menuIsOpen
        self.appIsActive = appIsActive
        self.restore = restore
    }

    /// From the Return key until the app's menu or panel closed. Auto-collapse waits meanwhile.
    var isActive: Bool {
        return phase != .idle
    }

    /// `completion` runs once: `.opened` as soon as the icon is pressed, or the
    /// reason nothing opened.
    func open(bundle newBundle: String, completion newCompletion: @escaping (PaletteOpenResult) -> Void) {
        if isActive {
            end(.unavailable, "superseded")
        }
        session += 1
        let id = session
        bundle = newBundle
        completion = newCompletion
        startedAt = now()
        liftedRestriction = false
        menuSeen = false
        activeSeen = false
        phase = .lifting
        after(timing.liftCap) { [weak self] in
            guard let self = self, id == self.session, self.phase == .lifting else { return }
            self.end(.unavailable, "liftTimeout")
        }
        allow(newBundle) { [weak self] lift in
            guard let self = self else { return }
            guard id == self.session, self.phase == .lifting else {
                // The session gave up (lift cap) or was superseded before the engine
                // answered, but the engine still recorded the app as allowed and
                // nobody else will end it. A live session that lifted its own app
                // is left alone.
                if lift == .lifted, !(self.isActive && self.liftedRestriction) { self.restore() }
                return
            }
            switch lift {
            case .unavailable:
                self.end(.unavailable, "unavailable")
            case .sensitive:
                self.end(.sensitive, "sensitive")
            case .lifted:
                self.liftedRestriction = true
                self.phase = .pressing
                self.liftedAt = self.now()
                self.after(self.timing.liftSettle) { [weak self] in self?.pressIcon(id) }
            case .alreadyShown:
                self.phase = .pressing
                self.liftedAt = self.now()
                self.pressIcon(id)
            }
        }
    }

    /// The user expanded or collapsed the bar: it stays as they left it.
    func userChangedBar() {
        liftedRestriction = false
    }

    private func pressIcon(_ id: Int) {
        guard id == session, phase == .pressing else { return }
        press(bundle) { [weak self] outcome in
            guard let self = self, id == self.session, self.phase == .pressing else { return }
            switch outcome {
            case .pressed:
                self.phase = .watching
                self.pressedAt = self.now()
                self.finishCompletion(.opened)
                self.poll(id)
            case .noItem:
                guard self.now() - self.liftedAt < self.timing.itemTimeout else { return self.end(.noItem, "noItem") }
                self.after(self.timing.pollInterval) { [weak self] in self?.pressIcon(id) }
            case .noPress:
                self.end(.noPress, "noPress")
            }
        }
    }

    private func poll(_ id: Int) {
        guard id == session, phase == .watching else { return }
        let elapsed = now() - pressedAt
        if menuIsOpen(bundle) {
            menuSeen = true
        } else if menuSeen {
            return end(.opened, "menuClosed")
        }
        if menuSeen {
            if elapsed >= timing.menuCap { return end(.opened, "menuCap") }
        } else if elapsed >= timing.menuAppearTimeout {
            // A panel, not a menu: it lasts while the app keeps focus.
            if appIsActive(bundle) {
                activeSeen = true
            } else if activeSeen {
                return end(.opened, "panelClosed")
            } else if elapsed >= timing.menuAppearTimeout + timing.panelGrace {
                return end(.opened, "nothingShown")
            }
            if elapsed >= timing.panelCap { return end(.opened, "panelCap") }
        }
        after(timing.pollInterval) { [weak self] in self?.poll(id) }
    }

    private func finishCompletion(_ result: PaletteOpenResult) {
        let done = completion
        completion = nil
        done?(result)
    }

    /// Every ending, the caps included, goes through here: the one app is hidden again
    /// when Hidden Bar lifted it and the user has not changed the bar since.
    private func end(_ result: PaletteOpenResult, _ reason: String) {
        let restores = liftedRestriction
        lastEndReason = reason
        phase = .idle
        liftedRestriction = false
        if restores {
            restore()
        }
        finishCompletion(result)
    }

    #if DEBUG
    var debugState: [String: Any] {
        return ["active": isActive, "bundle": bundle, "liftedRestriction": liftedRestriction,
                "menuSeen": menuSeen, "activeSeen": activeSeen, "lastEndReason": lastEndReason ?? "none"]
    }
    #endif
}
