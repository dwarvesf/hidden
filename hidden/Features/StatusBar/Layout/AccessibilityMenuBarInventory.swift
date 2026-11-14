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
        // Only app bundles own status items. Skipping the rest (dozens of WebKit
        // and XPC helpers, each of which would sit out the timeout) cuts the walk
        // from ~2.8s to ~1s.
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.processIdentifier != ownPID && $0.bundleURL?.pathExtension == "app" }
            .map { (pid: $0.processIdentifier, bundleIdentifier: $0.bundleIdentifier) }
        DispatchQueue.global(qos: .userInitiated).async {
            let start = Date()
            let items = Self.statusItems(of: apps)
            NSLog("NativeVisibility: inventory of \(apps.count) apps took \(Int(Date().timeIntervalSince(start) * 1000)) ms")
            DispatchQueue.main.async { completion(items) }
        }
    }

    // What one app's Accessibility read returned.
    enum AppRead: Equatable {
        case items([MenuBarInventoryItem])
        // The app did not answer within the messaging timeout.
        case timedOut
    }

    // Each app is an independent IPC round-trip, so they run concurrently; serial
    // walking made collapse lag by the sum of every app's latency. Results keep
    // the running-app order.
    private static func statusItems(of apps: [(pid: pid_t, bundleIdentifier: String?)]) -> [MenuBarInventoryItem] {
        return collect(count: apps.count) { index, timeout in
            statusItems(of: apps[index], timeout: timeout)
        }
    }

    // Reads every app concurrently with the short timeout, then reads the apps
    // that timed out once more with the longer one. Under concurrent load a slow
    // app can miss the short timeout; dropping it would hide it on collapse even
    // when it sits in the visible section. An app that times out twice is left out.
    static func collect(count: Int, read: (Int, Float) -> AppRead) -> [MenuBarInventoryItem] {
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
        return results.flatMap { result -> [MenuBarInventoryItem] in
            if case .items(let items) = result { return items }
            return []
        }
    }

    private static func statusItems(of app: (pid: pid_t, bundleIdentifier: String?), timeout: Float) -> AppRead {
        let element = AXUIElementCreateApplication(app.pid)
        // The default timeout is several seconds per app, and one busy or hung
        // app then stalls the collapse (measured: ~18s on a normal session).
        AXUIElementSetMessagingTimeout(element, timeout)
        var barValue: CFTypeRef?
        let barError = AXUIElementCopyAttributeValue(element, "AXExtrasMenuBar" as CFString, &barValue)
        if barError == .cannotComplete { return .timedOut }
        guard barError == .success, let bar = barValue else { return .items([]) }
        var childrenValue: CFTypeRef?
        let childrenError = AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &childrenValue)
        if childrenError == .cannotComplete { return .timedOut }
        guard childrenError == .success,
              let children = childrenValue as? [AXUIElement] else { return .items([]) }
        return .items(children.compactMap { child in
            frame(of: child).map { MenuBarInventoryItem(bundleIdentifier: app.bundleIdentifier, frame: $0) }
        })
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
