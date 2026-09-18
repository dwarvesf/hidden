//
//  MenuBarEngine.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
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

    // Display geometry changed. Re-applies the collapse to the live items when
    // collapsed, so a hot-plug does not leave a stale length behind (PR #354).
    func invalidateLayout()
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

// The controller owns and recreates the status items; engines only borrow them.
protocol MenuBarItemProvider: AnyObject {
    var toggleItem: NSStatusItem { get }
    var separatorItem: NSStatusItem { get }
    var alwaysHiddenItem: NSStatusItem? { get }
}
