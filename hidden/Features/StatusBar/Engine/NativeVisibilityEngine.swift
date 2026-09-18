//
//  NativeVisibilityEngine.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import AppKit

// macOS 27 hiding for the direct (non-App Store) build. Instead of inflating the
// separator, which macOS 27 ejects from the layout once it is too wide (#360),
// this reads which apps the user placed in each section and asks macOS to show
// only the allowed ones through the menu-bar visibility restriction behind
// assessment mode. macOS then hides the rest and reflows the bar itself, so the
// result does not depend on display width, the notch or the frontmost app's menus.
//
// The separators stay at their normal width and only mark section boundaries.
//
// Limits, all from what macOS 27 exposes:
// - Hiding is per app: an app with several icons hides or shows them together
//   (the most visible section wins).
// - macOS's own items (clock, Wi-Fi, Control Center...) are always kept visible:
//   Accessibility cannot tell them apart, so they cannot be mapped to sections.
// - Sections are read only while nothing is hidden, because hidden items report
//   stale positions. They are re-read on the next collapse from an unrestricted
//   bar, so an app launched while collapsed stays hidden until then, the same
//   as a new icon landing in the hidden section under the old mechanism.
final class NativeVisibilityEngine: MenuBarEngine {
    // System item identifiers to keep visible. Unknown identifiers are ignored,
    // so the range covers items a given Mac does not have (0-63 checked on 27.0).
    static let systemItemsToKeep = Array(0..<64)

    private weak var items: MenuBarItemProvider?
    private let inventory: MenuBarInventoryProviding
    private let visibility: NativeVisibilityProviding
    private let ownBundleIdentifier: String?
    private let separatorFrame: (NSStatusItem) -> CGRect?
    private let isLTR: () -> Bool

    private let expandedLength: CGFloat = 20

    // .calibrating stands for "an activation is in flight".
    private(set) var state: MenuBarEngineState = .expanded
    private(set) var layout: MenuBarLayout?

    private var assertion: NativeVisibilityAssertion?
    // Bumped whenever a pending activation must no longer win (an expand, a newer
    // activation); a late success is then invalidated straight away.
    private var generation = 0
    private var hasLoggedUnavailable = false

    private var alwaysHiddenEnabled = false
    private var alwaysHiddenSeparatorHidden = false

    init(items: MenuBarItemProvider,
         inventory: MenuBarInventoryProviding = AccessibilityMenuBarInventory(),
         visibility: NativeVisibilityProviding = NativeVisibilityBridge(),
         ownBundleIdentifier: String? = Bundle.main.bundleIdentifier,
         separatorFrame: @escaping (NSStatusItem) -> CGRect? = { $0.button?.window?.frame },
         isLTR: @escaping () -> Bool = { Constant.isUsingLTRLanguage }) {
        self.items = items
        self.inventory = inventory
        self.visibility = visibility
        self.ownBundleIdentifier = ownBundleIdentifier
        self.separatorFrame = separatorFrame
        self.isLTR = isLTR
    }

    func collapse(completion: @escaping (CollapseResult) -> Void) {
        switch state {
        case .collapsed:
            return completion(.collapsed)
        case .calibrating:
            // The activation in flight answers the request that started it.
            return
        case .expanded, .unavailable:
            break
        }
        items?.separatorItem.length = expandedLength

        guard visibility.isAvailable else {
            logUnavailableOnce("the native menu-bar visibility API is not available in this build or on this macOS")
            state = .unavailable
            return completion(.unavailable)
        }
        guard inventory.isAuthorized else {
            // Without Accessibility the sections cannot be read, and guessing would
            // hide icons the user kept visible. Not latched: it works as soon as
            // the permission is granted.
            inventory.requestAuthorization()
            logUnavailableOnce("Accessibility permission is needed to read the menu-bar sections")
            return completion(.unavailable)
        }
        if assertion == nil {
            layout = resolveLayout()
        }
        guard let layout = layout else {
            return completion(.unavailable)
        }

        state = .calibrating
        activate(allowing: layout.bundles(in: [.visible])) { [weak self] succeeded in
            guard let self = self else { return }
            self.state = succeeded ? .collapsed : .expanded
            completion(succeeded ? .collapsed : .unavailable)
        }
    }

    func expand() {
        items?.separatorItem.length = expandedLength
        state = .expanded
        applyExpandedPresentation()
    }

    func updateAlwaysHiddenSection(enabled: Bool, separatorHidden: Bool) {
        alwaysHiddenEnabled = enabled
        alwaysHiddenSeparatorHidden = separatorHidden
        items?.alwaysHiddenItem?.length = enabled ? expandedLength : 0
        if state == .expanded {
            applyExpandedPresentation()
        }
    }

    // Native hiding does not depend on display geometry, so only drop the cached
    // sections; the next read from an unrestricted bar replaces them.
    func invalidateLayout() {
        if assertion == nil {
            layout = nil
        }
    }

    // Expanded shows the hidden section; the always-hidden section stays hidden
    // while "hide separators" is on, otherwise everything is revealed by dropping
    // the restriction altogether.
    private func applyExpandedPresentation() {
        guard alwaysHiddenEnabled && alwaysHiddenSeparatorHidden, visibility.isAvailable, inventory.isAuthorized else {
            return releaseAssertion()
        }
        if assertion == nil {
            layout = resolveLayout()
        }
        guard let layout = layout else {
            return releaseAssertion()
        }
        activate(allowing: layout.bundles(in: [.visible, .hidden])) { _ in }
    }

    private func resolveLayout() -> MenuBarLayout? {
        guard let separator = items?.separatorItem,
              let boundary = separatorFrame(separator) else { return nil }
        let alwaysHiddenFrame = alwaysHiddenEnabled ? items?.alwaysHiddenItem.flatMap(separatorFrame) : nil
        return MenuBarLayoutResolver.resolve(inventory: inventory.snapshot(),
                                             separatorFrame: boundary,
                                             alwaysHiddenSeparatorFrame: alwaysHiddenFrame,
                                             isLTR: isLTR(),
                                             excludingBundle: ownBundleIdentifier)
    }

    // Activates the new restriction before dropping the old one, so switching
    // between collapsed and expanded never flashes the whole bar visible.
    private func activate(allowing bundles: [String], completion: @escaping (Bool) -> Void) {
        generation += 1
        let generation = self.generation
        let allowed = (ownBundleIdentifier.map { [$0] } ?? []) + bundles
        visibility.activate(allowedSystemItems: Self.systemItemsToKeep,
                            allowedBundleIdentifiers: allowed) { [weak self] result in
            guard let self = self, generation == self.generation else {
                if case .success(let stale) = result { stale.invalidate() }
                return
            }
            switch result {
            case .success(let newAssertion):
                let old = self.assertion
                self.assertion = newAssertion
                old?.invalidate()
                completion(true)
            case .failure(let error):
                // Fail open: never leave icons hidden after an error.
                NSLog("NativeVisibility: activation failed: \(error.localizedDescription)")
                self.releaseAssertion()
                completion(false)
            }
        }
    }

    private func releaseAssertion() {
        generation += 1
        assertion?.invalidate()
        assertion = nil
    }

    private func logUnavailableOnce(_ reason: String) {
        guard !hasLoggedUnavailable else { return }
        hasLoggedUnavailable = true
        NSLog("NativeVisibility: hiding unavailable: \(reason)")
    }
}
