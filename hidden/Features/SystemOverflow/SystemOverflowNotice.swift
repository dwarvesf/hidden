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

    private let indicator = SystemOverflowIndicator()
    private let policy = SystemOverflowNoticePolicy(defaults: .standard)
    private var isChecking = false

    func checkAfterCollapse(arrow: NSStatusItem) {
        guard MenuBarEngineFactory.usesNativeEngine(), policy.shouldShow(), !isChecking else { return }
        isChecking = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay) { [weak self, weak arrow] in
            guard let self = self else { return }
            self.isChecking = false
            guard let window = arrow?.button?.window else { return }
            guard SystemOverflowMatcher.isItemInSystemOverflow(windowFrame: window.frame,
                                                               hasScreen: window.screen != nil,
                                                               occlusionVisible: window.occlusionState.contains(.visible),
                                                               indicators: self.indicator.buttons) else { return }
            self.present()
        }
    }

    private func present() {
        policy.recordShown()
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Your menu bar is full".localized
        alert.informativeText = "macOS moved the Hidden Bar arrow into the « button. Click « to reach it, or use the Hidden Bar hotkey. To keep the arrow in view, move some icons to the left of the arrow.".localized
        alert.addButton(withTitle: "OK".localized)
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

#endif
