//
//  SystemOverflowIndicator.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

#if HIDDENBAR_NATIVE_VISIBILITY

import AppKit
import ApplicationServices

// macOS 27 draws its own « button in the menu bar when status items do not fit.
// MenuBarAgent owns it. Its Accessibility identifier is the only stable handle:
// the description is localized.
enum SystemOverflowState: Equatable {
    case absent
    case closed
    case open
}

/// One element of an Accessibility tree, reduced to what the search needs so the
/// matching can be unit tested with fakes.
protocol SystemOverflowNode {
    var identifier: String? { get }
    var frame: CGRect? { get }
    var children: [SystemOverflowNode] { get }
    func press() -> Bool
}

struct SystemOverflowReading: Equatable {
    let state: SystemOverflowState
    let frame: CGRect?
}

enum SystemOverflowMatcher {
    static let closedIdentifier = "menu-bar-overflow-indicator"
    static let openIdentifier = "menu-bar-overflow-indicator-expanded"
    // The button sits a few levels under the app's menu bar element.
    static let maxDepth = 5

    static func state(forIdentifier identifier: String?) -> SystemOverflowState {
        switch identifier {
        case closedIdentifier: return .closed
        case openIdentifier: return .open
        default: return .absent
        }
    }

    static func find(in root: SystemOverflowNode, depth: Int = 0) -> (node: SystemOverflowNode, state: SystemOverflowState)? {
        let state = state(forIdentifier: root.identifier)
        if state != .absent { return (root, state) }
        guard depth < maxDepth else { return nil }
        for child in root.children {
            if let found = find(in: child, depth: depth + 1) { return found }
        }
        return nil
    }

    // An item macOS moved into « is either parked off screen at (0, -30) with no
    // screen, or stacked at the « position with its window not visible. Occlusion
    // alone is not enough (an auto-hidden menu bar also clears it), so the
    // indicator must exist and the item must sit on it. Only the horizontal
    // position is compared: the Accessibility frame is top-left based, the window
    // frame bottom-left, and the menu bar is one row.
    static func isItemInSystemOverflow(windowFrame: CGRect,
                                       hasScreen: Bool,
                                       occlusionVisible: Bool,
                                       indicatorState: SystemOverflowState,
                                       indicatorFrame: CGRect?) -> Bool {
        guard indicatorState != .absent else { return false }
        if !hasScreen && abs(windowFrame.minX) < 1 && abs(windowFrame.minY + 30) < 1 { return true }
        guard !occlusionVisible, let indicatorFrame = indicatorFrame else { return false }
        return windowFrame.maxX > indicatorFrame.minX && windowFrame.minX < indicatorFrame.maxX
    }
}

final class SystemOverflowIndicator {
    static let agentBundleIdentifier = "com.apple.MenuBarAgent"

    private let root: () -> SystemOverflowNode?

    init(root: @escaping () -> SystemOverflowNode? = SystemOverflowIndicator.menuBarAgentRoot) {
        self.root = root
    }

    var reading: SystemOverflowReading {
        guard let root = root(), let found = SystemOverflowMatcher.find(in: root) else {
            return SystemOverflowReading(state: .absent, frame: nil)
        }
        return SystemOverflowReading(state: found.state, frame: found.node.frame)
    }

    var state: SystemOverflowState { reading.state }
    var frame: CGRect? { reading.frame }

    /// Opens the overflow when closed, closes it when open. False when absent.
    @discardableResult
    func press() -> Bool {
        guard let root = root(), let found = SystemOverflowMatcher.find(in: root) else { return false }
        return found.node.press()
    }

    static func menuBarAgentRoot() -> SystemOverflowNode? {
        guard let agent = NSRunningApplication.runningApplications(withBundleIdentifier: agentBundleIdentifier).first else { return nil }
        let element = AXUIElementCreateApplication(agent.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.5)
        return AccessibilityNode(element: element)
    }
}

private struct AccessibilityNode: SystemOverflowNode {
    let element: AXUIElement

    var identifier: String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXIdentifier" as CFString, &value) == .success else { return nil }
        return value as? String
    }

    var frame: CGRect? { AccessibilityMenuBarInventory.frame(of: element) }

    var children: [SystemOverflowNode] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement] else { return [] }
        return children.map { AccessibilityNode(element: $0) }
    }

    func press() -> Bool {
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }
}

#endif
