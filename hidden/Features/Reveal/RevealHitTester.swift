//
//  RevealHitTester.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import AppKit
import ApplicationServices

// Tells empty menu bar space from an icon or a menu title with one public
// Accessibility read at the pointer. Needs the Accessibility permission, and
// does not work inside the App Sandbox (see AccessibilityMenuBarInventory), so
// the App Store build never reports itself available and its settings hide the
// click row. The read runs off the main thread: a busy app can take its whole
// timeout to answer.
enum RevealHitTester {
    private static let messagingTimeout: Float = 0.15

    static func isAvailable() -> Bool {
        AXIsProcessTrusted()
    }

    static func resolve(at point: CGPoint, completion: @escaping (HitTarget) -> Void) {
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let menuBarOwner = NSWorkspace.shared.menuBarOwningApplication?.processIdentifier
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let axPoint = MenuBarBand.accessibilityPoint(fromAppKit: point, primaryScreenHeight: primaryHeight)
        DispatchQueue.global(qos: .userInteractive).async {
            let probe = probe(at: axPoint, frontmost: frontmost, menuBarOwner: menuBarOwner)
            let target = HitClassifier.target(for: probe)
            DispatchQueue.main.async { completion(target) }
        }
    }

    private static func probe(at axPoint: CGPoint, frontmost: pid_t?, menuBarOwner: pid_t?) -> HitProbe {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, messagingTimeout)
        var found: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(axPoint.x), Float(axPoint.y), &found) == .success,
              let element = found else {
            return HitProbe(role: nil, ownerPID: nil, frontmostPID: frontmost, menuBarOwnerPID: menuBarOwner)
        }
        var roleValue: CFTypeRef?
        let role = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success
            ? roleValue as? String : nil
        var pid: pid_t = 0
        let owner: Int32? = AXUIElementGetPid(element, &pid) == .success ? pid : nil
        return HitProbe(role: role, ownerPID: owner, frontmostPID: frontmost, menuBarOwnerPID: menuBarOwner)
    }
}
