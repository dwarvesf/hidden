//
//  SystemOverflowNotice.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

#if HIDDENBAR_NATIVE_VISIBILITY

import AppKit

// Direct build on macOS 27 only. When the bar is full, macOS moves the leftmost
// visible item into its « button, and after a collapse that is the arrow. The
// hotkey still works, but a click user sees the arrow vanish. Say so once.
struct SystemOverflowNoticePolicy {
    static let shownKey = "systemOverflowNoticeShown"

    let defaults: UserDefaults

    func shouldShow() -> Bool {
        !defaults.bool(forKey: Self.shownKey)
    }

    func recordShown() {
        defaults.set(true, forKey: Self.shownKey)
    }
}

final class SystemOverflowNotice {
    static let shared = SystemOverflowNotice()

    // The bar needs a moment to relayout after a collapse before the arrow's
    // window settles in its final place.
    private static let settleDelay: TimeInterval = 1.5
    private static let retryDelay: TimeInterval = 1

    private let indicator = SystemOverflowIndicator()
    private let policy = SystemOverflowNoticePolicy(defaults: .standard)
    private var isChecking = false

    /// Call after a collapse the user asked for (click or hotkey). `isCollapsed`
    /// is asked again when the delayed check runs, so an expand in between cancels it.
    func checkAfterCollapse(arrow: NSStatusItem, isCollapsed: @escaping () -> Bool) {
        guard MenuBarEngineFactory.usesNativeEngine(), policy.shouldShow(), !isChecking else { return }
        isChecking = true
        check(arrow: arrow, isCollapsed: isCollapsed, after: Self.settleDelay, retriesLeft: 1)
    }

    private func check(arrow: NSStatusItem, isCollapsed: @escaping () -> Bool, after delay: TimeInterval, retriesLeft: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak arrow] in
            guard let self = self else { return }
            guard isCollapsed(), let arrow = arrow, arrow.button?.window != nil else { self.isChecking = false; return }
            self.indicator.readButtons { [weak self, weak arrow] buttons in
                guard let self = self else { return }
                guard isCollapsed(), let arrow = arrow, let window = arrow.button?.window else { self.isChecking = false; return }
                let hasScreen = window.screen != nil
                let occlusionVisible = window.occlusionState.contains(.visible)
                // MenuBarAgent can time out while it relays out; an arrow that looks
                // hidden with no « read is worth one more read.
                if buttons.isEmpty, retriesLeft > 0, !hasScreen || !occlusionVisible {
                    self.check(arrow: arrow, isCollapsed: isCollapsed, after: Self.retryDelay, retriesLeft: retriesLeft - 1)
                    return
                }
                guard SystemOverflowMatcher.isItemInSystemOverflow(windowFrame: window.frame,
                                                                   hasScreen: hasScreen,
                                                                   occlusionVisible: occlusionVisible,
                                                                   indicators: buttons) else {
                    self.isChecking = false
                    return
                }
                self.present()
            }
        }
    }

    // A modal alert run inside a dispatch block would hold the main queue (the
    // toggle guard, engine completions, auto-collapse timers) until dismissed.
    // The run loop block does not.
    private func present() {
        RunLoop.main.perform(inModes: [.default]) { [weak self] in
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "Your menu bar is full".localized
            alert.informativeText = "macOS moved the Hidden Bar arrow into the « button. Click « to reach it, or use the Hidden Bar hotkey. To keep the arrow in view, move some icons to the left of the arrow.".localized
            alert.addButton(withTitle: "OK".localized)
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            self?.policy.recordShown()
            self?.isChecking = false
        }
    }
}

#endif
