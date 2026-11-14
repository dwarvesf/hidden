//
//  AccessibilityMenuBarInventory.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import AppKit
import ApplicationServices

// Lists other apps' status items through public Accessibility API: every running
// app's AXExtrasMenuBar children, with the owning bundle from the process.
// Needs the Accessibility permission, and does not work inside the App Sandbox
// (the sandbox denies the mach-lookup to com.apple.axserver even when the
// permission is granted), so only the non-sandboxed direct build uses it.
final class AccessibilityMenuBarInventory: MenuBarInventoryProviding {
    private static let messagingTimeout: Float = 0.1
    // A second try for apps too busy for the first (iStat Menus, #429).
    private static let retryTimeout: Float = 1.0

    private typealias App = (pid: pid_t, bundleIdentifier: String?, name: String?)

    private var hasRequestedAuthorization = false

    var isAuthorized: Bool {
        return AXIsProcessTrusted()
    }

    // Shows the system prompt once per launch; asking on every collapse would
    // nag while the user is still in System Settings.
    func requestAuthorization() {
        guard !hasRequestedAuthorization else { return }
        hasRequestedAuthorization = true
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // Accessibility round-trips to every app take about a second in total, so the
    // walk runs off the main thread.
    func snapshot(completion: @escaping ([MenuBarInventoryItem]) -> Void) {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let apps: [App] = NSWorkspace.shared.runningApplications
            .filter { $0.processIdentifier != ownPID && Self.mayOwnStatusItems(bundleURL: $0.bundleURL, bundleIdentifier: $0.bundleIdentifier) }
            .map { (pid: $0.processIdentifier, bundleIdentifier: $0.bundleIdentifier, name: $0.localizedName) }
        DispatchQueue.global(qos: .userInitiated).async {
            let start = Date()
            let items = Self.statusItems(of: apps)
            NSLog("NativeVisibility: inventory of \(apps.count) apps took \(Int(Date().timeIntervalSince(start) * 1000)) ms")
            DispatchQueue.main.async { completion(items) }
        }
    }

    // Apps and bare executables (scripts, helpers without an Info.plist) can own
    // status items. Skipping XPC services and extensions (dozens of WebKit
    // helpers, each of which would sit out the timeout) cuts the walk from ~2.8s
    // to ~1s.
    static func mayOwnStatusItems(bundleURL: URL?, bundleIdentifier: String?) -> Bool {
        guard let url = bundleURL else { return bundleIdentifier == nil }
        return !["xpc", "appex"].contains(url.pathExtension)
    }

    private enum Reading {
        case items([MenuBarInventoryItem])
        case noAnswer
        case noStatusItems
    }

    // Each app is an independent IPC round-trip, so they run concurrently; serial
    // walking made collapse lag by the sum of every app's latency. Results keep
    // the running-app order.
    private static func statusItems(of apps: [App]) -> [MenuBarInventoryItem] {
        var perApp = [[MenuBarInventoryItem]](repeating: [], count: apps.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: apps.count) { index in
            let found = statusItems(of: apps[index])
            lock.lock()
            perApp[index] = found
            lock.unlock()
        }
        return perApp.flatMap { $0 }
    }

    private static func statusItems(of app: App) -> [MenuBarInventoryItem] {
        var reading = read(app, timeout: messagingTimeout)
        if case .noAnswer = reading {
            reading = read(app, timeout: retryTimeout)
        }
        switch reading {
        case .items(let found):
            return found
        case .noAnswer:
            // Unknown items stay visible. Without a bundle id nothing could be
            // allowed anyway, and such processes are mostly daemons.
            guard app.bundleIdentifier != nil else { return [] }
            return [MenuBarInventoryItem(bundleIdentifier: app.bundleIdentifier, frame: .zero,
                                         isUnreadable: true, ownerName: app.name)]
        case .noStatusItems:
            return []
        }
    }

    private static func read(_ app: App, timeout: Float) -> Reading {
        let element = AXUIElementCreateApplication(app.pid)
        // The default timeout is several seconds per app, and one busy or hung
        // app then stalls the collapse (measured: ~18s on a normal session).
        AXUIElementSetMessagingTimeout(element, timeout)
        var barValue: CFTypeRef?
        let barError = AXUIElementCopyAttributeValue(element, "AXExtrasMenuBar" as CFString, &barValue)
        if barError == .cannotComplete { return .noAnswer }
        guard barError == .success, let bar = barValue else { return .noStatusItems }
        var childrenValue: CFTypeRef?
        let childrenError = AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &childrenValue)
        if childrenError == .cannotComplete { return .noAnswer }
        guard childrenError == .success, let children = childrenValue as? [AXUIElement] else { return .noStatusItems }
        let isSystemOwner = app.bundleIdentifier.map(MenuBarLayoutResolver.systemItemOwners.contains) ?? false
        return .items(children.map { child in
            guard let frame = frame(of: child) else {
                return MenuBarInventoryItem(bundleIdentifier: app.bundleIdentifier, frame: .zero,
                                            isUnreadable: true, ownerName: app.name)
            }
            return MenuBarInventoryItem(bundleIdentifier: app.bundleIdentifier, frame: frame,
                                        systemIdentifier: isSystemOwner ? identifier(of: child) : nil,
                                        ownerName: app.name)
        })
    }

    // On 27.2 a system extra is a hosting view whose one child, the menu bar
    // item, carries the identifier (com.apple.menuextra.clock...).
    private static func identifier(of element: AXUIElement) -> String? {
        if let identifier = string(element, "AXIdentifier") {
            return identifier
        }
        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let child = (childrenValue as? [AXUIElement])?.first else { return nil }
        return string(child, "AXIdentifier")
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    // Accessibility frames use a top-left origin, AppKit's bottom-left. Only the
    // horizontal position matters for sections, and x is the same in both.
    static func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: position, size: size)
    }
}
