//
//  SystemOverflowNotice.swift
//  Hidden Bar
//
//  Copyright © 2026 Console Labs. All rights reserved.
//

#if HIDDENBAR_NATIVE_VISIBILITY

import AppKit

// Direct build on macOS 27 only. When the bar is full, macOS moves the leftmost
// visible item into its « button, and after a collapse that is the arrow. The
// hotkey still works, but a click user sees the arrow vanish. Say so once.
struct SystemOverflowNoticePolicy {
    static let shownKey = "systemOverflowNoticeShown"
    // The expand notice has its own flag: seeing one does not silence the other.
    static let expandShownKey = "systemOverflowExpandNoticeShown"

    let defaults: UserDefaults

    func shouldShow() -> Bool {
        !defaults.bool(forKey: Self.shownKey)
    }

    func recordShown() {
        defaults.set(true, forKey: Self.shownKey)
    }

    func shouldShowAfterExpand() -> Bool {
        !defaults.bool(forKey: Self.expandShownKey)
    }

    func recordExpandShown() {
        defaults.set(true, forKey: Self.expandShownKey)
    }

    /// The notice shows only for a bar that is expanded, with a revealed icon that
    /// macOS put into «, and only until it was shown once.
    static func shouldShowAfterExpand(isExpanded: Bool, hiddenItemInOverflow: Bool, alreadyShown: Bool) -> Bool {
        isExpanded && hiddenItemInOverflow && !alreadyShown
    }
}

// After an expand the icons that were hidden are back on the bar. Those that do
// not fit right of the notch (or on a narrow display) go into «, and the user
// then needs a second click. macOS 27 lists only the items that fit, so such an
// app is missing from Accessibility, or its item sits under « or on no display.
enum SystemOverflowExpandMatcher {
    /// The bundles of `hidden` that macOS moved into «. Only running third-party
    /// apps count: system extras follow their own rules, and an app that is not
    /// running has no icon to lose.
    static func bundlesInOverflow(hidden: Set<String>,
                                  running: Set<String>,
                                  inventory: [MenuBarInventoryItem],
                                  indicators: [SystemOverflowButton],
                                  displays: [MenuBarDisplay],
                                  primaryScreenMaxY: CGFloat?) -> Set<String> {
        guard !indicators.isEmpty else { return [] }
        let system = MenuBarLayoutResolver.systemItemOwners
        return hidden.filter { bundle in
            guard running.contains(bundle), !system.contains(bundle),
                  bundle != MenuBarLayoutResolver.systemExtrasBundle else { return false }
            let items = inventory.filter { $0.bundleIdentifier == bundle }
            if items.isEmpty { return true }
            // An app that did not answer cannot be judged.
            if items.contains(where: { $0.isUnreadable }) { return false }
            return items.contains { isInOverflow($0.frame, indicators: indicators, displays: displays, primaryScreenMaxY: primaryScreenMaxY) }
        }
    }

    // `frame` is an Accessibility frame (top-left origin, global).
    private static func isInOverflow(_ frame: CGRect,
                                     indicators: [SystemOverflowButton],
                                     displays: [MenuBarDisplay],
                                     primaryScreenMaxY: CGFloat?) -> Bool {
        if !displays.isEmpty, MenuBarDisplay.containing(accessibilityFrame: frame, in: displays) == nil { return true }
        guard let maxY = primaryScreenMaxY else { return false }
        let cocoa = SystemOverflowMatcher.cocoaFrame(fromAccessibilityFrame: frame, primaryScreenMaxY: maxY)
        let centre = CGPoint(x: cocoa.midX, y: cocoa.midY)
        return indicators.contains { button in
            guard let buttonFrame = button.frame else { return false }
            return buttonFrame.insetBy(dx: -SystemOverflowMatcher.slack, dy: -SystemOverflowMatcher.slack).contains(centre)
        }
    }
}

final class SystemOverflowNotice {
    static let shared = SystemOverflowNotice()

    // The bar needs a moment to relayout after a collapse before the arrow's
    // window settles in its final place.
    private static let settleDelay: TimeInterval = 1.5
    private static let retryDelay: TimeInterval = 1

    private let indicator = SystemOverflowIndicator()
    private let policy = SystemOverflowNoticePolicy(defaults: AppDefaults.store)
    private var isChecking = false
    private var isCheckingExpand = false

    /// Call after a collapse the user asked for (click or hotkey). `isCollapsed`
    /// is asked again when the delayed check runs, so an expand in between cancels it.
    func checkAfterCollapse(arrow: NSStatusItem, isCollapsed: @escaping () -> Bool) {
        guard MenuBarEngineFactory.usesNativeEngine(), policy.shouldShow(), !isChecking else { return }
        isChecking = true
        check(arrow: arrow, isCollapsed: isCollapsed, after: Self.settleDelay, retriesLeft: 1)
    }

    /// Call after an expand the user asked for (click or hotkey). `hiddenBundles` is
    /// what the bar hid before, read now; `isExpanded` is asked again before the
    /// notice, so a collapse in between cancels it.
    func checkAfterExpand(hiddenBundles: Set<String>, isExpanded: @escaping () -> Bool,
                          inventory: MenuBarInventoryProviding = AccessibilityMenuBarInventory()) {
        guard MenuBarEngineFactory.usesNativeEngine(), policy.shouldShowAfterExpand(),
              !hiddenBundles.isEmpty, !isCheckingExpand, inventory.isAuthorized else { return }
        isCheckingExpand = true
        // The revealed icons need a moment to settle before macOS has placed or overflowed them.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay) { [weak self] in
            guard let self = self else { return }
            guard isExpanded() else { self.isCheckingExpand = false; return }
            self.indicator.readButtons { [weak self] buttons in
                guard let self = self else { return }
                // No « means nothing overflowed; the inventory walk is skipped.
                guard isExpanded(), !buttons.isEmpty else { self.isCheckingExpand = false; return }
                inventory.snapshot { [weak self] items in
                    guard let self = self else { return }
                    let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
                    let moved = SystemOverflowExpandMatcher.bundlesInOverflow(
                        hidden: hiddenBundles, running: running, inventory: items, indicators: buttons,
                        displays: MenuBarDisplay.current(), primaryScreenMaxY: NSScreen.screens.first?.frame.maxY)
                    guard SystemOverflowNoticePolicy.shouldShowAfterExpand(isExpanded: isExpanded(),
                                                                           hiddenItemInOverflow: !moved.isEmpty,
                                                                           alreadyShown: !self.policy.shouldShowAfterExpand()) else {
                        self.isCheckingExpand = false
                        return
                    }
                    NSLog("SystemOverflow: expanded; macOS moved \(moved.sorted()) into «")
                    self.presentExpandNotice()
                }
            }
        }
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
            self?.runAlert(Self.makeAlert(title: "Your menu bar is full".localized,
                                          text: "macOS moved the Hidden Bar arrow into the « button. Click « to reach it, or use the Hidden Bar hotkey. To keep the arrow in view, move some icons to the left of the arrow.".localized))
            self?.policy.recordShown()
            self?.isChecking = false
        }
    }

    private func presentExpandNotice() {
        RunLoop.main.perform(inModes: [.default]) { [weak self] in
            // Recorded before the alert opens: the bar may collapse behind it, and a
            // second expand must not stack another one.
            self?.policy.recordExpandShown()
            self?.runAlert(Self.makeExpandAlert())
            self?.isCheckingExpand = false
        }
    }

    static func makeExpandAlert() -> NSAlert {
        makeAlert(title: "Some icons are in the « button".localized,
                  text: "Some icons do not fit in the menu bar, so macOS moved them into its own « button. Click « to see them. To make room, move icons you rarely use to the always-hidden section.".localized)
    }

    private static func makeAlert(title: String, text: String) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: "OK".localized)
        return alert
    }

    private func runAlert(_ alert: NSAlert) {
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

#endif
