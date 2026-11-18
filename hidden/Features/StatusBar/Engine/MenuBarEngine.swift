//
//  MenuBarEngine.swift
//  Hidden Bar
//
//  Copyright © 2026 Console Labs. All rights reserved.
//

import AppKit

// StatusBarController decides WHAT the user wants (collapsed or expanded, which
// sections exist); an engine decides HOW the menu bar is made to do it. Keeping
// the mechanics here lets an OS release that changes menu-bar layout (#360) get
// its own engine without version checks spreading through the controller.
protocol MenuBarEngine: AnyObject {
    var state: MenuBarEngineState { get }

    func collapse(completion: @escaping (CollapseResult) -> Void)
    func expand()

    func updateAlwaysHiddenSection(enabled: Bool, separatorHidden: Bool)

    // Whether the user's ⌘-drag arrangement lets the engine hide anything: its
    // hiding boundary must sit on the hidden side of the arrow. The controller
    // does not collapse otherwise.
    var isArrangementValid: Bool { get }

    // Whether the always-hidden separator sits beyond the regular hidden section.
    var isAlwaysHiddenSeparatorPlaced: Bool { get }

    // Whether macOS has placed the items the arrangement checks read. Until then
    // those checks answer false, so the launch collapse waits for this.
    var isArrangementKnown: Bool { get }

    // Display geometry changed. Re-applies each hidden section to the live items,
    // so a hot-plug does not leave a stale length behind (PR #354).
    func invalidateLayout()

    // macOS 27: a clock click expanded the bar for Notification Center, which is
    // still open; auto-collapse waits.
    var defersAutoCollapse: Bool { get }

    // Bundles whose items the engine last read in the menu bar, so auto-collapse
    // can tell a menu-bar app's popup window. Empty when the engine reads none.
    var menuBarItemOwners: Set<String> { get }

    // Bundles the last read put in the hidden section: what an expand brings back
    // onto the bar. Empty when the engine reads none.
    var hiddenSectionBundles: Set<String> { get }

    // The user expanded or collapsed the bar, so a clock click no longer
    // collapses it when Notification Center closes.
    func userChangedBar()

    // The "hide separators" state a collapse should leave behind. True when the
    // engine keeps the always-hidden section hidden on every expand, so
    // Option-click shows it only until the next collapse.
    func separatorsHiddenForCollapse(current: Bool) -> Bool

    // Whether the arrow's menu offers "Show everything" (expand and show the
    // always-hidden section), the recovery for icons lost there.
    var offersShowEverything: Bool { get }

    // The palette opens a hidden app's own menu: this lets that one app's icon
    // show until `endTemporaryAllow`. `.alreadyShown` when nothing is hiding it,
    // `.unavailable` when the engine cannot lift one app (nothing changed then).
    func allowTemporarily(_ bundle: String, completion: @escaping (PaletteLift) -> Void)

    // Puts back what `allowTemporarily` lifted. Does nothing when the bar changed since.
    func endTemporaryAllow()
}

extension MenuBarEngine {
    var isArrangementKnown: Bool { return true }
    var defersAutoCollapse: Bool { return false }
    var menuBarItemOwners: Set<String> { return [] }
    var hiddenSectionBundles: Set<String> { return [] }
    func userChangedBar() {}
    func separatorsHiddenForCollapse(current: Bool) -> Bool { return current }
    var offersShowEverything: Bool { return false }
    func allowTemporarily(_ bundle: String, completion: @escaping (PaletteLift) -> Void) { completion(.unavailable) }
    func endTemporaryAllow() {}
}

enum MenuBarEngineState {
    case expanded
    case calibrating
    case collapsed
    case unavailable
}

enum CollapseResult {
    case collapsed
    case unavailable
}

enum MenuBarOrder {
    // True when `item` sits on the hidden side of `boundary`: to its left in a
    // left-to-right layout, to its right otherwise. False when either is not on
    // screen, since nothing can be judged then.
    static func isItem(_ item: NSStatusItem?, onHiddenSideOf boundary: NSStatusItem?) -> Bool {
        return isOrigin(origin(of: item), onHiddenSideOf: origin(of: boundary),
                        leftToRight: Constant.isUsingLTRLanguage)
    }

    static func isPlaced(_ item: NSStatusItem?) -> Bool {
        return isPlaced(origin(of: item))
    }

    // macOS 26 reports every status item at (0, 0) for about a second after
    // launch, before it places them (#336). Two unplaced items compare equal and
    // would pass, so a collapse could run on a saved order that has the arrow
    // inside the hidden zone and hide the arrow itself.
    static func isPlaced(_ origin: CGPoint?) -> Bool {
        guard let origin = origin else { return false }
        return origin != .zero
    }

    static func isOrigin(_ item: CGPoint?, onHiddenSideOf boundary: CGPoint?, leftToRight: Bool) -> Bool {
        guard let item = item, let boundary = boundary, isPlaced(item), isPlaced(boundary) else { return false }
        return leftToRight ? boundary.x >= item.x : boundary.x <= item.x
    }

    private static func origin(of item: NSStatusItem?) -> CGPoint? {
        return item?.button?.window?.frame.origin
    }
}

// The controller owns and recreates the status items; engines only borrow them.
protocol MenuBarItemProvider: AnyObject {
    var toggleItem: NSStatusItem { get }
    var separatorItem: NSStatusItem { get }
    var alwaysHiddenItem: NSStatusItem? { get }
}
