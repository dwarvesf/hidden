//
//  LegacyLengthEngine.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import AppKit

// Hides icons by inflating the separator until everything to its left leaves the
// visible bar. macOS <= 26 reflows around any length, so the length only has to
// be large enough to cover the widest attached display.
final class LegacyLengthEngine: MenuBarEngine {
    private weak var items: MenuBarItemProvider?
    private let screenWidths: () -> [CGFloat]

    private let expandedLength: CGFloat = 20

    // SPEC-003 (macOS 27 hide-mechanism). macOS 27 re-architected the menu bar so
    // inflating the separator length may no longer push items off-screen (#360).
    // This is DIAGNOSTIC ONLY: on the first collapse with the menu-bar window
    // ready, log the separator geometry so a macOS 27 run reveals which signal
    // (if any) distinguishes "length honored" from "ignored". No behavior change.
    // The degrade ACTION is deliberately NOT shipped: review found the trigger
    // unverifiable without 27 hardware, and a false positive would disable hiding
    // for a working user. The action lands once this log calibrates the signal.
    private var hideMechanismChecked = false

    // The recovery patches (#224, #242) apply up to macOS 26, where this engine
    // hides. On 27 (the App Store build) inflating is ejected anyway, and
    // nothing changes there.
    private let osMajorVersion: Int

    init(items: MenuBarItemProvider,
         screenWidths: @escaping () -> [CGFloat] = { NSScreen.screens.map { $0.frame.width } },
         osMajorVersion: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion) {
        self.items = items
        self.screenWidths = screenWidths
        self.osMajorVersion = osMajorVersion
    }

    private var appliesRecoveryPatches: Bool {
        return osMajorVersion < 27
    }

    // The always-hidden section used to stay hidden only while "hide
    // separators" was on (Option-click), so with the default it showed on every
    // expand (#224). Every collapse now hides it again; Option-click shows it
    // until the next collapse.
    func separatorsHiddenForCollapse(current: Bool) -> Bool {
        return appliesRecoveryPatches ? true : current
    }

    // "Show everything" in the arrow's menu: expand and show the always-hidden
    // section too, for icons the user lost there (#242).
    var offersShowEverything: Bool {
        return appliesRecoveryPatches
    }

    // Derived from the live length rather than stored, and compared with > rather
    // than ==, so the state survives the collapse length being recomputed while
    // collapsed (PR #354).
    var state: MenuBarEngineState {
        guard let separator = items?.separatorItem else { return .expanded }
        return separator.length > expandedLength ? .collapsed : .expanded
    }

    private var collapsedLength: CGFloat {
        // The menubar replicates across every attached display, so the collapse
        // length must cover the WIDEST screen, not NSScreen.main (the focused one);
        // sizing from a narrower screen leaks hidden icons on wider displays.
        // frame.width, not visibleFrame: the menubar spans the full frame width.
        let screenWidth = screenWidths().max() ?? 1728
        // Keep collapse length bounded to avoid pathological layout/memory behavior;
        // macOS enforces a hard 10,000pt maximum on NSStatusItem.length (PR #354).
        return max(500, min(screenWidth * 2, 10_000))
    }

    func collapse(completion: @escaping (CollapseResult) -> Void) {
        items?.separatorItem.length = collapsedLength
        completion(.collapsed)
        verifyHideMechanismIfNeeded()
    }

    func expand() {
        items?.separatorItem.length = expandedLength
    }

    func updateAlwaysHiddenSection(enabled: Bool, separatorHidden: Bool) {
        let length: CGFloat
        if separatorHidden {
            length = enabled ? collapsedLength : 0
        } else {
            length = enabled ? expandedLength : 0
        }
        items?.alwaysHiddenItem?.length = length
    }

    // The separator is what widens, so it must sit between the hidden icons and
    // the arrow, and the always-hidden separator further out still.
    var isArrangementValid: Bool {
        return MenuBarOrder.isItem(items?.separatorItem, onHiddenSideOf: items?.toggleItem)
    }

    var isAlwaysHiddenSeparatorPlaced: Bool {
        return MenuBarOrder.isItem(items?.alwaysHiddenItem, onHiddenSideOf: items?.separatorItem)
    }

    var isArrangementKnown: Bool {
        return MenuBarOrder.isPlaced(items?.toggleItem) && MenuBarOrder.isPlaced(items?.separatorItem)
    }

    // Each section is hidden on its own: an expanded bar can still have the
    // always-hidden section hidden, and its spacer must cover a newly attached
    // wider display too. Only inflated items are touched, so each keeps its state.
    func invalidateLayout() {
        let length = collapsedLength
        for item in [items?.separatorItem, items?.alwaysHiddenItem].compactMap({ $0 })
            where item.length > expandedLength {
            item.length = length
        }
    }

    // After a collapse, confirm on the next runloop tick (so layout settles) that
    // the separator actually claimed its inflated width. macOS <= 26 honors it;
    // a macOS that ignores NSStatusItem.length leaves the slot narrow, meaning
    // hiding did nothing. Checked once: cheap, and the OS behavior won't change
    // mid-session.
    private func verifyHideMechanismIfNeeded() {
        guard !hideMechanismChecked else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.state == .collapsed else { return }
            // Need the separator's backing window to measure. If it is not up yet
            // (early launch), do NOT burn the one-shot check: return and let a
            // later collapse retry once the window exists.
            guard let separator = self.items?.separatorItem,
                  let separatorButton = separator.button,
                  let window = separatorButton.window else { return }
            self.hideMechanismChecked = true
            // Log several geometry signals. On macOS <= 26 the inflation is
            // honored; on macOS 27 it may be ignored. Which of these tracks the
            // requested length is exactly what a 27 capture must reveal before any
            // degrade action can trigger on a sound signal.
            let requested = self.collapsedLength
            let windowWidth = window.frame.width
            let buttonWidth = separatorButton.frame.width
            NSLog("HideMechanism: requested=\(requested) windowWidth=\(windowWidth) buttonWidth=\(buttonWidth) length=\(separator.length)")
        }
    }
}
