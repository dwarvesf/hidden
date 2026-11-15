//
//  PaletteItemPresser.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

#if HIDDENBAR_NATIVE_VISIBILITY
import AppKit
import ApplicationServices

/// Presses an app's menu-bar icon through public Accessibility API, so its own
/// menu opens, and tells whether that menu is still up. Needs the Accessibility
/// permission the engine needs already; reads no screen content: window owner,
/// layer and bounds need no Screen Recording.
enum PaletteItemPresser {
    // A menu bar app may be busy; the lookup stays short so a retry can follow.
    private static let messagingTimeout: Float = 0.5
    // NSPopUpMenuWindowLevel: menus and popovers sit here; status item buttons are lower.
    static let menuWindowLayer = 101

    /// Looks for an icon of `bundle` inside a menu bar and presses it. Runs the
    /// Accessibility reads off the main thread; `completion` runs on the main thread.
    static func press(bundle: String, completion: @escaping (PalettePressOutcome) -> Void) {
        let pids = runningPids(of: bundle)
        let bars = menuBarBands()
        DispatchQueue.global(qos: .userInteractive).async {
            let outcome = press(pids: pids, bars: bars)
            DispatchQueue.main.async { completion(outcome) }
        }
    }

    static func isMenuOpen(bundle: String) -> Bool {
        let pids = Set(runningPids(of: bundle))
        guard !pids.isEmpty,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return false }
        return windows.contains { window in
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t, pids.contains(pid),
                  let layer = window[kCGWindowLayer as String] as? Int else { return false }
            return layer >= menuWindowLayer
        }
    }

    static func isActive(bundle: String) -> Bool {
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundle).contains { $0.isActive }
    }

    private static func runningPids(of bundle: String) -> [pid_t] {
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundle)
            .filter { !$0.isTerminated }.map(\.processIdentifier)
    }

    // The strip of each display where the menu bar is, in Accessibility's
    // top-left coordinates. A status item that reports a frame elsewhere is a
    // stale read of a hidden one and is not pressed.
    private static func menuBarBands() -> [CGRect] {
        guard let primaryHeight = NSScreen.screens.first?.frame.maxY else { return [] }
        return NSScreen.screens.map { screen in
            let height = max(screen.frame.maxY - screen.visibleFrame.maxY, screen.safeAreaInsets.top, NSStatusBar.system.thickness)
            return CGRect(x: screen.frame.minX, y: primaryHeight - screen.frame.maxY, width: screen.frame.width, height: height)
        }
    }

    private static func press(pids: [pid_t], bars: [CGRect]) -> PalettePressOutcome {
        var sawItem = false
        for pid in pids {
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, messagingTimeout)
            guard let bar = value(of: app, "AXExtrasMenuBar"),
                  CFGetTypeID(bar) == AXUIElementGetTypeID() else { continue }
            for item in children(of: bar as! AXUIElement) {
                guard let frame = AccessibilityMenuBarInventory.frame(of: item),
                      bars.contains(where: { $0.intersects(frame) && $0.contains(CGPoint(x: frame.midX, y: frame.midY)) }) else { continue }
                sawItem = true
                // The item may be the press target itself, or host it (bar > group > item).
                for target in [item] + children(of: item) where actions(of: target).contains(kAXPressAction as String) {
                    return AXUIElementPerformAction(target, kAXPressAction as CFString) == .success ? .pressed : .noPress
                }
            }
        }
        return sawItem ? .noPress : .noItem
    }

    private static func value(of element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        return value(of: element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    private static func actions(of element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
        return names as? [String] ?? []
    }
}
#endif
