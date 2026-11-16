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
    // Apps that time out in the concurrent pass get one more read, alone and with
    // more time, so a busy app is not dropped from the allow list and hidden.
    private static let retryTimeout: Float = 0.5

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

    // What one app's Accessibility read returned.
    enum AppRead: Equatable {
        case items([MenuBarInventoryItem])
        // The app did not answer within the messaging timeout.
        case timedOut
        // The app answers but exposes no Accessibility tree, so its items and
        // their positions cannot be read. Not read again.
        case refused
    }

    // An app element that lists attributes but not even a role has turned its
    // Accessibility off (Little Snitch on 27.2 lists only a frame); any AppKit or
    // SwiftUI app lists its role, whether or not it has menu-bar items.
    static func refusesAccessibility(attributeNames: [String]?) -> Bool {
        guard let names = attributeNames else { return false }
        return !names.contains(kAXRoleAttribute as String)
    }

    // Each app is an independent IPC round-trip, so they run concurrently; serial
    // walking made collapse lag by the sum of every app's latency. Results keep
    // the running-app order.
    private static func statusItems(of apps: [App]) -> [MenuBarInventoryItem] {
        return collect(count: apps.count,
                       read: { index, timeout in read(apps[index], timeout: timeout) },
                       unanswered: { index in
                           // Unknown items stay visible, wherever they sit: an app that
                           // never answered, or one that answers but shows Accessibility
                           // nothing (Little Snitch, #502), which otherwise is left out of
                           // the allow list and hidden on every collapse. Without a bundle
                           // id nothing could be allowed anyway, and such processes are
                           // mostly daemons.
                           let app = apps[index]
                           guard app.bundleIdentifier != nil else { return [] }
                           return [MenuBarInventoryItem(bundleIdentifier: app.bundleIdentifier, frame: .zero,
                                                        isUnreadable: true, ownerName: app.name)]
                       })
    }

    // Reads every app concurrently with the short timeout, then reads the apps
    // that timed out once more with the longer one. Under concurrent load a slow
    // app can miss the short timeout; dropping it would hide it on collapse even
    // when it sits in the visible section. An app that times out twice, or that
    // refuses Accessibility, gets the items `unanswered` returns for it.
    static func collect(count: Int, read: (Int, Float) -> AppRead,
                        unanswered: (Int) -> [MenuBarInventoryItem]) -> [MenuBarInventoryItem] {
        var results = [AppRead](repeating: .items([]), count: count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: count) { index in
            let result = read(index, messagingTimeout)
            lock.lock()
            results[index] = result
            lock.unlock()
        }
        let retry = results.indices.filter { results[$0] == .timedOut }
        if !retry.isEmpty {
            DispatchQueue.concurrentPerform(iterations: retry.count) { position in
                let index = retry[position]
                let result = read(index, retryTimeout)
                lock.lock()
                results[index] = result
                lock.unlock()
            }
            let stillMissing = retry.filter { results[$0] == .timedOut }.count
            NSLog("NativeVisibility: re-read \(retry.count) apps that timed out, \(stillMissing) still missing")
        }
        return results.indices.flatMap { index -> [MenuBarInventoryItem] in
            if case .items(let items) = results[index] { return items }
            return unanswered(index)
        }
    }

    private static func read(_ app: App, timeout: Float) -> AppRead {
        let element = AXUIElementCreateApplication(app.pid)
        // The default timeout is several seconds per app, and one busy or hung
        // app then stalls the collapse (measured: ~18s on a normal session).
        AXUIElementSetMessagingTimeout(element, timeout)
        var barValue: CFTypeRef?
        let barError = AXUIElementCopyAttributeValue(element, "AXExtrasMenuBar" as CFString, &barValue)
        if barError == .cannotComplete { return .timedOut }
        guard barError == .success, let bar = barValue else {
            var names: CFArray?
            let namesError = AXUIElementCopyAttributeNames(element, &names)
            return refusesAccessibility(attributeNames: namesError == .success ? names as? [String] : nil) ? .refused : .items([])
        }
        var childrenValue: CFTypeRef?
        let childrenError = AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &childrenValue)
        if childrenError == .cannotComplete { return .timedOut }
        guard childrenError == .success, let children = childrenValue as? [AXUIElement] else { return .items([]) }
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
