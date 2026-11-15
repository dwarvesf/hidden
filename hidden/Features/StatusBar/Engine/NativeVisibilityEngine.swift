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
// The arrow is the boundary: apps left of it (LTR) are hidden, apps right of it
// stay visible. The regular separator is not needed and is taken out of the
// bar; even at zero width macOS keeps a gap for it. The always-hidden
// separator, when enabled, marks the third section; it shows while that section
// is shown so it can be ⌘-dragged, and is taken out of the bar while the section
// is hidden (collapsed, or expanded with "hide separators" on), where macOS has
// already removed everything it would separate. macOS puts it back where the
// user left it, which is what defines that section.
//
// Limits, all from what macOS 27 exposes:
// - Hiding is per app: an app with several icons hides or shows them together
//   (the most visible section wins).
// - macOS's own items (clock, Wi-Fi, Control Center...) are always kept visible:
//   Accessibility cannot tell them apart, so they cannot be mapped to sections.
//   SystemUIServer's legacy Menu Extras (Time Machine...) are the exception:
//   none was observed with a system item identifier, so they are sectioned
//   per bundle instead.
// - Sections are read only while nothing is hidden, because hidden items report
//   stale positions. They are re-read on the next collapse from an unrestricted
//   bar, so an app launched while collapsed stays hidden until then, the same
//   as a new icon landing in the hidden section under the old mechanism.
// - The restriction is assessment mode, which makes macOS ignore the clock, so
//   Notification Center cannot open from it (#410). A click on the clock lifts
//   the restriction for a moment and presses it (MenuBarClock); hidden icons
//   can flash while it is lifted.
final class NativeVisibilityEngine: MenuBarEngine {
    // System item identifiers to keep visible. Unknown identifiers are ignored,
    // so the range covers items a given Mac does not have (0-63 checked on 27.0).
    static let systemItemsToKeep = Array(0..<64)

    private weak var items: MenuBarItemProvider?
    private let inventory: MenuBarInventoryProviding
    private let visibility: NativeVisibilityProviding
    private let clock: MenuBarClockProviding
    private let ownBundleIdentifier: String?
    private let itemFrame: (NSStatusItem) -> CGRect?
    private let displays: () -> [MenuBarDisplay]
    private let isLTR: () -> Bool

    private let expandedLength: CGFloat = 20

    // .calibrating stands for "an activation is in flight".
    private(set) var state: MenuBarEngineState = .expanded
    private(set) var layout: MenuBarLayout?
    // The last read that listed every item, to fill in a read from an
    // overflowing menu bar. Kept across display changes: sections are per app.
    private var lastCompleteLayout: MenuBarLayout?

    private var assertion: NativeVisibilityAssertion?
    // What the held assertion allows besides Hidden Bar, and the generation it was
    // activated in, which stays current while nothing newer is in flight.
    private var assertionBundles: [String] = []
    private var assertionGeneration = 0
    // Bumped whenever a pending activation must no longer win (an expand, a newer
    // activation); a late success is then invalidated straight away.
    private var generation = 0
    private var lastUnavailableReason: String?

    private var alwaysHiddenEnabled = false
    private var alwaysHiddenSeparatorHidden = false

    // Items right of the arrow that the allow-list cannot keep visible: an item
    // whose owner has no bundle id, or a system extra no system item id covers
    // (Focus, Now Playing, User...) that macOS hid although Control Center's
    // bundle was allowed; those extras are remembered here. By default they are
    // hidden along with the rest, as before (Preferences lists them). Opting in
    // (`pausesHidingForUnkeepableItems`) keeps the whole bar shown instead.
    private var unkeepableSystemItems: Set<String> = []
    private let pausesHidingForUnkeepableItems: () -> Bool
    // Hidden extras leave Accessibility only once the bar has reflowed.
    var scheduleVisibilityCheck: (@escaping () -> Void) -> Void = {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: $0)
    }

    init(items: MenuBarItemProvider,
         inventory: MenuBarInventoryProviding = AccessibilityMenuBarInventory(),
         visibility: NativeVisibilityProviding = NativeVisibilityBridge(),
         clock: MenuBarClockProviding = SystemMenuBarClock(),
         ownBundleIdentifier: String? = Bundle.main.bundleIdentifier,
         itemFrame: @escaping (NSStatusItem) -> CGRect? = { $0.button?.window?.frame },
         displays: @escaping () -> [MenuBarDisplay] = MenuBarDisplay.current,
         isLTR: @escaping () -> Bool = { Constant.isUsingLTRLanguage },
         pausesHidingForUnkeepableItems: @escaping () -> Bool = { false }) {
        self.items = items
        self.pausesHidingForUnkeepableItems = pausesHidingForUnkeepableItems
        self.inventory = inventory
        self.visibility = visibility
        self.clock = clock
        self.ownBundleIdentifier = ownBundleIdentifier
        self.itemFrame = itemFrame
        self.displays = displays
        self.isLTR = isLTR
        items.separatorItem.isVisible = false
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
        if !hidesAlwaysHiddenSection {
            setSeparatorsVisible(true)
        }

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
        state = .calibrating
        withLayout { [weak self] layout in
            guard let self = self else { return }
            guard let layout = layout else {
                self.logUnavailableOnce("the arrow's position cannot be read yet")
                self.state = .expanded
                return completion(.unavailable)
            }
            if self.pausesHidingForUnkeepableItems(),
               let reason = layout.reasonToKeepBarWhole(unkeepableSystemItems: self.unkeepableSystemItems) {
                self.logUnavailableOnce(reason)
                self.state = .expanded
                return completion(.unavailable)
            }
            self.activate(allowing: layout.bundles(in: [.visible])) { [weak self] succeeded in
                guard let self = self else { return }
                guard succeeded else {
                    self.state = .expanded
                    return completion(.unavailable)
                }
                self.checkStillShown(layout.unprovenVisibleSystemItems) { [weak self] shown in
                    guard let self = self else { return }
                    self.state = shown ? .collapsed : .expanded
                    if shown {
                        self.setSeparatorsVisible(false)
                    }
                    completion(shown ? .collapsed : .unavailable)
                }
            }
        }
    }

    func expand() {
        state = .expanded
        applyExpandedPresentation()
    }

    func updateAlwaysHiddenSection(enabled: Bool, separatorHidden: Bool) {
        alwaysHiddenEnabled = enabled
        alwaysHiddenSeparatorHidden = separatorHidden
        switch state {
        case .collapsed:
            // A separator created while collapsed arrives visible.
            setSeparatorsVisible(false)
        case .expanded:
            applyExpandedPresentation()
        case .calibrating, .unavailable:
            setSeparatorsVisible(true)
        }
    }

    private var hidesAlwaysHiddenSection: Bool {
        return alwaysHiddenEnabled && alwaysHiddenSeparatorHidden
    }

    // Sections are per app and come from the arrangement, which a display change
    // does not alter, so a held restriction stays right and the bar stays
    // collapsed. Only an unused cache is dropped; the next read from an
    // unrestricted bar measures against the displays connected then.
    func invalidateLayout() {
        if assertion == nil {
            layout = nil
        }
    }

    // Expanded shows the hidden section; the always-hidden section stays hidden
    // while "hide separators" is on, otherwise everything is revealed by dropping
    // the restriction altogether. Its separator goes and comes back with it, only
    // once the icons are hidden, so it never disappears on its own.
    private func applyExpandedPresentation() {
        guard hidesAlwaysHiddenSection, visibility.isAvailable, inventory.isAuthorized else {
            return revealAll()
        }
        withLayout { [weak self] layout in
            guard let self = self else { return }
            guard let layout = layout else {
                return self.revealAll()
            }
            self.activate(allowing: layout.bundles(in: [.visible, .hidden])) { [weak self] succeeded in
                self?.setSeparatorsVisible(!succeeded)
            }
        }
    }

    private func revealAll() {
        releaseAssertion()
        setSeparatorsVisible(true)
    }

    // The sections as the user arranged them. Read fresh only from an
    // unrestricted bar; while a restriction is active the cached ones stand in.
    // Superseded by any later expand or activation, like an activation is.
    private func withLayout(_ body: @escaping (MenuBarLayout?) -> Void) {
        if assertion != nil {
            return body(layout)
        }
        guard let arrow = items?.toggleItem,
              var boundary = itemFrame(arrow) else { return body(nil) }
        var alwaysHiddenFrame = alwaysHiddenEnabled ? items?.alwaysHiddenItem.flatMap(itemFrame) : nil
        #if DEBUG
        if let x = Self.debugBoundaryX {
            boundary.origin.x = x - boundary.width / 2
        }
        if alwaysHiddenEnabled, let x = Self.debugAlwaysHiddenX {
            alwaysHiddenFrame = CGRect(x: x, y: boundary.minY, width: 1, height: boundary.height)
        }
        #endif
        let isLTR = self.isLTR()
        generation += 1
        let generation = self.generation
        inventory.snapshot { [weak self] inventory in
            guard let self = self, generation == self.generation else { return }
            // Read after the snapshot, which takes about a second: a display
            // attached meanwhile is then known. An arrow on no display has no
            // edge to measure the sections from.
            let displays = self.displays()
            guard displays.isEmpty || MenuBarDisplay.containing(appKitFrame: boundary, in: displays) != nil else {
                NSLog("NativeVisibility: the arrow at \(NSStringFromRect(boundary)) is on no display \(displays.map { NSStringFromRect($0.appKitFrame) })")
                return body(nil)
            }
            var layout = MenuBarLayoutResolver.resolve(inventory: inventory,
                                                       separatorFrame: boundary,
                                                       alwaysHiddenSeparatorFrame: alwaysHiddenFrame,
                                                       displays: displays,
                                                       isLTR: isLTR,
                                                       excludingBundle: self.ownBundleIdentifier)
            if layout.isIncomplete {
                // Apps macOS left out would be hidden although they may be
                // right of the arrow; with no complete read to take them from,
                // nothing may be hidden.
                guard let complete = self.lastCompleteLayout else {
                    NSLog("NativeVisibility: the active menu bar overflows and no complete read exists yet; leaving the bar whole")
                    return body(nil)
                }
                layout = layout.fillingIn(from: complete)
                NSLog("NativeVisibility: the active menu bar overflows; apps it does not list keep their last known section")
            } else {
                self.lastCompleteLayout = layout
            }
            NSLog("NativeVisibility: arrow at x=\(boundary.midX); visible \(layout.bundles(in: [.visible])), hidden \(layout.bundles(in: [.hidden])), always hidden \(layout.bundles(in: [.alwaysHidden]))")
            if !layout.unnameableVisibleItems.isEmpty || !layout.unprovenVisibleSystemItems.isEmpty {
                NSLog("NativeVisibility: visible without a bundle id \(layout.unnameableVisibleItems); visible system extras to check \(layout.unprovenVisibleSystemItems)")
            }
            self.layout = layout
            body(layout)
        }
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
                self.assertionBundles = bundles
                self.assertionGeneration = generation
                old?.invalidate()
                self.watchClock()
                completion(true)
            case .failure(let error):
                // Fail open: never leave icons hidden after an error.
                NSLog("NativeVisibility: activation failed: \(error.localizedDescription)")
                self.releaseAssertion()
                completion(false)
            }
        }
    }

    // The always-hidden separator is taken out of the bar while its section is
    // hidden; a zero-width item would still be there and clickable.
    private func setSeparatorsVisible(_ visible: Bool) {
        items?.separatorItem.isVisible = false
        let shown = visible && alwaysHiddenEnabled
        items?.alwaysHiddenItem?.length = shown ? expandedLength : 0
        items?.alwaysHiddenItem?.isVisible = shown
    }

    // Any arrangement works: whatever sits left of the arrow is the hidden section.
    var isArrangementValid: Bool {
        return true
    }

    var isAlwaysHiddenSeparatorPlaced: Bool {
        return MenuBarOrder.isItem(items?.alwaysHiddenItem, onHiddenSideOf: items?.toggleItem)
    }

    private func releaseAssertion() {
        generation += 1
        assertion?.invalidate()
        assertion = nil
        watchClock()
    }

    // Any held restriction, collapsed or expanded with the always-hidden section
    // hidden, stops the clock from opening Notification Center.
    private func watchClock() {
        clock.onClick = assertion == nil ? nil : { [weak self] location in
            self?.openNotificationCenter(from: location)
        }
    }

    // macOS ignores the clock while a restriction is held, so lift it just long
    // enough for a press to land, then put the same one back. The panel stays
    // open under the restriction; hidden icons can show for a moment.
    private func openNotificationCenter(from location: CGPoint) {
        // Not while an activation, a section read or a collapse's visibility
        // check is in flight: lifting now would cancel it, and a cancelled
        // collapse never reports back, leaving the bar stuck calibrating.
        guard assertion != nil, generation == assertionGeneration, state != .calibrating else { return }
        NSLog("NativeVisibility: lifting the restriction for a click on the clock")
        let bundles = assertionBundles
        releaseAssertion()
        let generation = self.generation
        clock.press(at: location) { [weak self] in
            // An expand or collapse meanwhile already applied what the user wants.
            guard let self = self, generation == self.generation else { return }
            self.activate(allowing: bundles) { [weak self] succeeded in
                guard let self = self, !succeeded else { return }
                self.state = .expanded
                self.setSeparatorsVisible(true)
            }
        }
    }

    // Logged when the reason changes, so a retried collapse does not spam.
    private func logUnavailableOnce(_ reason: String) {
        guard reason != lastUnavailableReason else { return }
        lastUnavailableReason = reason
        NSLog("NativeVisibility: hiding unavailable: \(reason)")
    }

    // Checks whether macOS hid a system extra the allow-list could only try to
    // keep, and remembers the ones it did. By default the bar stays collapsed
    // and the check only feeds the Preferences note. With the opt-in, the
    // restriction is dropped and later collapses keep the bar whole while such an
    // extra is right of the arrow, instead of flashing it hidden.
    private func checkStillShown(_ expected: [String], completion: @escaping (Bool) -> Void) {
        let unchecked = expected.filter { !unkeepableSystemItems.contains($0) }
        guard !unchecked.isEmpty else { return completion(true) }
        let pauses = pausesHidingForUnkeepableItems()
        if !pauses {
            completion(true)
        }
        let generation = self.generation
        scheduleVisibilityCheck { [weak self] in
            guard let self = self, generation == self.generation else { return }
            self.inventory.snapshot { [weak self] inventory in
                guard let self = self, generation == self.generation else { return }
                let missing = MenuBarLayoutResolver.missingSystemItems(unchecked, in: inventory)
                if !missing.isEmpty {
                    self.rememberUnkeepable(missing)
                }
                guard pauses else {
                    if !missing.isEmpty {
                        NSLog("NativeVisibility: macOS also hides \(missing) although they sit right of the arrow")
                    }
                    return
                }
                guard missing.isEmpty else {
                    NSLog("NativeVisibility: macOS hid \(missing) although they sit right of the arrow; keeping the bar whole while they are there")
                    self.releaseAssertion()
                    return completion(false)
                }
                completion(true)
            }
        }
    }

    // What Preferences shows as "macOS 27 also hides".
    static private(set) var knownUnkeepableSystemItems: [String] = []

    private func rememberUnkeepable(_ identifiers: [String]) {
        unkeepableSystemItems.formUnion(identifiers)
        Self.knownUnkeepableSystemItems = unkeepableSystemItems.sorted()
        NotificationCenter.default.post(name: .unkeepableSystemItemsChanged, object: nil)
    }

    // "com.apple.menuextra.now-playing" -> "Now Playing".
    static func displayName(ofSystemItem identifier: String) -> String {
        let known = ["focusmode": "Focus", "now-playing": "Now Playing", "user": "User",
                     "siri": "Siri", "stagemanager": "Stage Manager", "timemachine": "Time Machine"]
        let name = identifier.components(separatedBy: ".").last ?? identifier
        return known[name] ?? name.replacingOccurrences(of: "-", with: " ").capitalized
    }
}

extension Notification.Name {
    // Posted on the main queue when NativeVisibilityEngine.knownUnkeepableSystemItems changes.
    static let unkeepableSystemItemsChanged = Notification.Name("unkeepableSystemItemsChanged")
}

#if DEBUG
// Test hooks (Debug builds only); see StatusBarController's debug extension.
extension NativeVisibilityEngine {
    // Section boundaries to use instead of the items' real positions, so a
    // harness can place sections without ⌘-dragging anything.
    static var debugBoundaryX: CGFloat?
    static var debugAlwaysHiddenX: CGFloat?

    var debugState: [String: Any] {
        var sections: [String: String] = [:]
        layout?.sections.forEach { sections[$0.key] = String(describing: $0.value) }
        return [
            "assertionHeld": assertion != nil,
            "allowedBundles": assertion == nil ? [] : assertionBundles,
            "sections": sections,
            "clockWatched": clock.onClick != nil,
            "unprovenVisibleSystemItems": layout?.unprovenVisibleSystemItems ?? [],
            "unnameableVisibleItems": layout?.unnameableVisibleItems ?? [],
            "unkeepableSystemItems": unkeepableSystemItems.sorted(),
            "pausesHidingForUnkeepableItems": pausesHidingForUnkeepableItems(),
            "lastUnavailableReason": lastUnavailableReason ?? NSNull(),
            "displays": displays().map { NSStringFromRect($0.appKitFrame) },
            "debugBoundaryX": Self.debugBoundaryX.map { Double($0) } ?? NSNull(),
            "debugAlwaysHiddenX": Self.debugAlwaysHiddenX.map { Double($0) } ?? NSNull()
        ]
    }

    // Runs the clock-click handler the global mouse monitor would run, with the
    // replayed press posted to MenuBarAgent's process instead of the HID stream.
    func debugClockClicked(at location: CGPoint, postingTo pid: pid_t) {
        SystemMenuBarClock.debugPostToPid = pid
        clock.onClick?(location)
    }
}
#endif
