//
//  AutoCollapsePopupGuard.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import AppKit

// One on-screen window as CGWindowList reports it. Frames use global display
// coordinates: origin at the primary display's top-left, y grows downward.
struct OnScreenWindow: Equatable {
    let ownerPID: pid_t
    let layer: Int
    let frame: CGRect
}

// One display's menu bar strip (same coordinates as OnScreenWindow) and the
// display's height.
struct PopupGuardDisplay: Equatable {
    let menuBarBand: CGRect
    let height: CGFloat
}

protocol OnScreenWindowListing {
    func onScreenWindows() -> [OnScreenWindow]
}

// Owner, layer and bounds need no Screen Recording permission, unlike window
// names. Same query as the clock's Notification Center check.
final class CGOnScreenWindowList: OnScreenWindowListing {
    func onScreenWindows() -> [OnScreenWindow] {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return windows.compactMap { window in
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t,
                  let layer = window[kCGWindowLayer as String] as? Int,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else { return nil }
            return OnScreenWindow(ownerPID: pid, layer: layer, frame: frame)
        }
    }
}

// Keeps auto-collapse from closing the bar under a popup that hangs from the
// menu bar (#319): a menu-bar app's popover or menu, or Notification Center,
// whoever expanded the bar. Read only when the auto-hide timer fires, never
// polled. After `cap` of deferring for popups the bar collapses anyway.
final class AutoCollapsePopupGuard {
    static let popUpMenuLayer = Int(CGWindowLevelForKey(.popUpMenuWindow))
    static let statusLayer = Int(CGWindowLevelForKey(.statusWindow))
    static let notificationCenterBundleIdentifier = "com.apple.notificationcenterui"
    static let defaultCap: TimeInterval = 600
    // A popover's arrow can leave a small gap under the menu bar.
    static let bandTolerance: CGFloat = 8

    private let windows: OnScreenWindowListing
    private let displays: () -> [PopupGuardDisplay]
    private let bundleIdentifier: (pid_t) -> String?
    private let menuBarItemOwners: () -> Set<String>
    private let now: () -> TimeInterval
    private let ownPID: pid_t
    private let cap: TimeInterval
    private let log: (String) -> Void
    private var deferringSince: TimeInterval?

    // menuBarItemOwners: bundles the engine read in the menu bar. On macOS 27 the
    // menu bar draws every app's items itself, so the window list has no
    // per-item windows to name the owners; before 27 each item is a status
    // window in the band and is picked up from the same read.
    init(windows: OnScreenWindowListing = CGOnScreenWindowList(),
         displays: @escaping () -> [PopupGuardDisplay] = AutoCollapsePopupGuard.screenDisplays,
         bundleIdentifier: @escaping (pid_t) -> String? = { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier },
         menuBarItemOwners: @escaping () -> Set<String> = { [] },
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         ownPID: pid_t = ProcessInfo.processInfo.processIdentifier,
         cap: TimeInterval = AutoCollapsePopupGuard.defaultCap,
         log: @escaping (String) -> Void = { NSLog("%@", $0) }) {
        self.windows = windows
        self.displays = displays
        self.bundleIdentifier = bundleIdentifier
        self.menuBarItemOwners = menuBarItemOwners
        self.now = now
        self.ownPID = ownPID
        self.cap = cap
        self.log = log
    }

    // Called when the auto-hide timer fires: true to re-arm instead of collapsing.
    func defersCollapse() -> Bool {
        guard let holder = popupWindow() else {
            deferringSince = nil
            return false
        }
        let time = now()
        if deferringSince == nil {
            // Owner and layer only: never a window title or other content.
            log("AutoCollapse: holding for a popup from \(bundleIdentifier(holder.ownerPID) ?? "pid \(holder.ownerPID)") at layer \(holder.layer)")
        }
        let since = deferringSince ?? time
        deferringSince = since
        if time - since >= cap {
            NSLog("AutoCollapse: a menu-bar popup has been open for %.0f s; collapsing anyway", time - since)
            return false
        }
        return true
    }

    // The bar was expanded again: the cap starts over.
    func reset() {
        deferringSince = nil
    }

    func isPopupOpen() -> Bool {
        return popupWindow() != nil
    }

    // The first window that counts as a popup hanging from the menu bar.
    private func popupWindow() -> OnScreenWindow? {
        let displays = self.displays()
        let all = windows.onScreenWindows().filter { $0.ownerPID != ownPID }
        guard !displays.isEmpty, !all.isEmpty else { return nil }
        let bands = displays.map(\.menuBarBand).filter { !$0.isEmpty }
        let panelHeight = (displays.map(\.height).min() ?? 0) / 2

        var bundles: [pid_t: String?] = [:]
        func bundle(of pid: pid_t) -> String? {
            if let known = bundles[pid] { return known }
            let found = bundleIdentifier(pid)
            bundles[pid] = found
            return found
        }

        // Before macOS 27 each menu-bar item is a status window inside the band.
        let statusItemOwners = Set(all.filter { window in
            window.layer == Self.statusLayer && bands.contains { $0.insetBy(dx: 0, dy: -1).contains(window.frame) }
        }.map(\.ownerPID))
        var itemOwnerBundles: Set<String>?

        for window in all {
            // Notification Center: a panel as tall as the screen; banners are
            // short and widgets sit below the desktop (negative layers).
            if window.layer >= 0, window.frame.height >= panelHeight, panelHeight > 0,
               bundle(of: window.ownerPID) == Self.notificationCenterBundleIdentifier {
                return window
            }
            guard let band = bands.first(where: { Self.hangs(window.frame, from: $0) }) else { continue }
            if window.layer == Self.popUpMenuLayer || window.layer == Self.statusLayer {
                return window
            }
            // A menu-bar app's own window under the band, at any level. Wide
            // windows are an app's document windows touching the top of the
            // screen, not popovers.
            guard window.layer >= 0, window.frame.width <= band.width / 2 else { continue }
            if statusItemOwners.contains(window.ownerPID) { return window }
            if itemOwnerBundles == nil { itemOwnerBundles = menuBarItemOwners() }
            if let id = bundle(of: window.ownerPID), itemOwnerBundles?.contains(id) == true {
                return window
            }
        }
        return nil
    }

    // Touches the band (or sits just under it) and reaches below it, so the
    // menu bar's own windows and its items are not popups.
    static func hangs(_ frame: CGRect, from band: CGRect) -> Bool {
        let reach = CGRect(x: band.minX, y: band.minY, width: band.width, height: band.height + bandTolerance)
        return frame.intersects(reach) && frame.maxY > band.maxY + 1 && frame.minY >= band.minY - 1
    }

    // Same band as the clock's menu-bar hit test.
    static func screenDisplays() -> [PopupGuardDisplay] {
        guard let primaryHeight = NSScreen.screens.first?.frame.maxY else { return [] }
        return NSScreen.screens.map { screen in
            let top = primaryHeight - screen.frame.maxY
            let height = max(screen.frame.maxY - screen.visibleFrame.maxY, screen.safeAreaInsets.top, NSStatusBar.system.thickness)
            return PopupGuardDisplay(menuBarBand: CGRect(x: screen.frame.minX, y: top, width: screen.frame.width, height: height),
                                     height: screen.frame.height)
        }
    }
}
