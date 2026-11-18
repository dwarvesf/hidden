//
//  AccessibilityPermission.swift
//  Hidden Bar
//
//  Copyright © 2026 Console Labs. All rights reserved.
//

import AppKit
import ApplicationServices

protocol AccessibilityTrustProviding {
    var isTrusted: Bool { get }
}

struct SystemAccessibilityTrust: AccessibilityTrustProviding {
    var isTrusted: Bool { return AXIsProcessTrusted() }
}

// macOS 27 native hiding reads the menu-bar sections through Accessibility.
// Without the permission a collapse hides nothing and the arrow looks broken, so
// this tells the UI when to explain it, and when a grant should retry the collapse.
final class AccessibilityPermission {
    // macOS posts this when any app's Accessibility grant changes.
    static let systemChangeNotification = Notification.Name("com.apple.accessibility.api")

    private let needsPermission: Bool
    private let trust: AccessibilityTrustProviding
    private let notifications: NotificationCenter
    private let recheckDelay: TimeInterval
    private var observer: NSObjectProtocol?
    private var wasTrusted: Bool

    // Called after every system notification, once the trust value has settled.
    var onChange: (() -> Void)?
    // Called only when this app's own permission went from missing to granted.
    var onRestored: (() -> Void)?

    // The legacy engine and the App Store build never need the permission.
    init(needsPermission: Bool,
         trust: AccessibilityTrustProviding = SystemAccessibilityTrust(),
         notifications: NotificationCenter = DistributedNotificationCenter.default(),
         recheckDelay: TimeInterval = 0.5) {
        self.needsPermission = needsPermission
        self.trust = trust
        self.notifications = notifications
        self.recheckDelay = recheckDelay
        wasTrusted = !needsPermission || trust.isTrusted
        guard needsPermission else { return }
        // The trust value lags the notification slightly, hence the delay.
        observer = notifications.addObserver(forName: Self.systemChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + self.recheckDelay) { [weak self] in
                self?.recheck()
            }
        }
    }

    deinit {
        if let observer = observer { notifications.removeObserver(observer) }
    }

    var isMissing: Bool {
        return needsPermission && !trust.isTrusted
    }

    // A click on the expanded arrow cannot hide anything without the permission;
    // opening Preferences, which explains it, beats a click that does nothing.
    func arrowClickOpensPreferences(isCollapsed: Bool) -> Bool {
        return !isCollapsed && isMissing
    }

    // Other apps' grant changes post the same notification; only a change of
    // this app's own permission from missing to granted retries the collapse.
    func recheck() {
        let isTrusted = !isMissing
        let restored = !wasTrusted && isTrusted
        wasTrusted = isTrusted
        onChange?()
        if restored { onRestored?() }
    }

    // The prompt adds Hidden Bar to the Accessibility list so the user only has to
    // flip the switch; the pane opens too, because the prompt shows at most once
    // per launch and is easy to dismiss.
    static func openSystemSettings() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
