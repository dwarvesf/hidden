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
    /// Accessibility frame: top-left origin, global.
    var frame: CGRect? { get }
    var children: [SystemOverflowNode] { get }
}

/// One « button, with its frame already in Cocoa (bottom-left origin) coordinates.
struct SystemOverflowButton: Equatable {
    let state: SystemOverflowState
    let frame: CGRect?
}

enum SystemOverflowMatcher {
    static let closedIdentifier = "menu-bar-overflow-indicator"
    static let openIdentifier = "menu-bar-overflow-indicator-expanded"
    // The button sits a few levels under the app's menu bar element.
    static let maxDepth = 5
    // Overflowed items sit on the button, not just near it; a few points absorb rounding.
    static let slack: CGFloat = 4

    static func state(forIdentifier identifier: String?) -> SystemOverflowState {
        switch identifier {
        case closedIdentifier: return .closed
        case openIdentifier: return .open
        default: return .absent
        }
    }

    // MenuBarAgent draws one « per display, and a narrow display overflows while
    // the main bar fits, so the first match is not necessarily the right one.
    static func findAll(in root: SystemOverflowNode, depth: Int = 0) -> [(node: SystemOverflowNode, state: SystemOverflowState)] {
        let state = state(forIdentifier: root.identifier)
        if state != .absent { return [(root, state)] }
        guard depth < maxDepth else { return [] }
        return root.children.flatMap { findAll(in: $0, depth: depth + 1) }
    }

    // The live tree reaches the same « through two parents. One « per identifier
    // and frame; a button with no readable frame cannot be compared, so it stays.
    static func findUnique(in root: SystemOverflowNode) -> [(node: SystemOverflowNode, state: SystemOverflowState)] {
        var seen: [(identifier: String?, frame: CGRect)] = []
        return findAll(in: root).filter { found in
            guard let frame = found.node.frame else { return true }
            if seen.contains(where: { $0.identifier == found.node.identifier && $0.frame == frame }) { return false }
            seen.append((found.node.identifier, frame))
            return true
        }
    }

    // Accessibility frames are top-left based and global; AppKit's are bottom-left,
    // flipped about the top edge of the screen that holds the menu bar origin.
    static func cocoaFrame(fromAccessibilityFrame frame: CGRect, primaryScreenMaxY: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryScreenMaxY - frame.minY - frame.height,
               width: frame.width, height: frame.height)
    }

    // An item macOS moved into « is either parked off screen at (0, -30) with no
    // screen, or stacked under a « with its window not visible. Occlusion alone is
    // not enough (an auto-hidden bar also clears it, and an arrow next to « would
    // intersect it), so a « must exist and the item's centre must sit under one.
    // Frames are all Cocoa.
    static func isItemInSystemOverflow(windowFrame: CGRect,
                                       hasScreen: Bool,
                                       occlusionVisible: Bool,
                                       indicators: [SystemOverflowButton]) -> Bool {
        guard !indicators.isEmpty else { return false }
        if !hasScreen && abs(windowFrame.minX) < 1 && abs(windowFrame.minY + 30) < 1 { return true }
        guard !occlusionVisible else { return false }
        return indicators.contains { button in
            guard let frame = button.frame else { return false }
            return frame.insetBy(dx: -slack, dy: -slack).contains(CGPoint(x: windowFrame.midX, y: windowFrame.midY))
        }
    }
}

final class SystemOverflowIndicator {
    static let agentBundleIdentifier = "com.apple.MenuBarAgent"
    // MenuBarAgent can stall while it relays out; every element, not just the
    // app's, gets this short timeout instead of the multi-second default.
    static let messagingTimeout: Float = 0.5

    private let root: () -> SystemOverflowNode?
    private let primaryScreenMaxY: () -> CGFloat?
    private let queue = DispatchQueue(label: "SystemOverflowIndicator")

    init(root: @escaping () -> SystemOverflowNode? = SystemOverflowIndicator.menuBarAgentRoot,
         primaryScreenMaxY: @escaping () -> CGFloat? = { NSScreen.screens.first?.frame.maxY }) {
        self.root = root
        self.primaryScreenMaxY = primaryScreenMaxY
    }

    private func read(primaryScreenMaxY maxY: CGFloat?) -> [SystemOverflowButton] {
        guard let root = root() else { return [] }
        return SystemOverflowMatcher.findUnique(in: root).map { found in
            let frame = found.node.frame.flatMap { axFrame in
                maxY.map { SystemOverflowMatcher.cocoaFrame(fromAccessibilityFrame: axFrame, primaryScreenMaxY: $0) }
            }
            return SystemOverflowButton(state: found.state, frame: frame)
        }
    }

    /// Every « on the bar, one per display that overflows. Empty when none.
    /// Walks Accessibility synchronously; the app reads through `readButtons`.
    var buttons: [SystemOverflowButton] { read(primaryScreenMaxY: primaryScreenMaxY()) }

    var state: SystemOverflowState {
        let states = buttons.map { $0.state }
        if states.contains(.open) { return .open }
        return states.isEmpty ? .absent : .closed
    }

    /// The same read on a background queue, delivered on the main queue, so a busy
    /// MenuBarAgent cannot stall the main thread.
    func readButtons(completion: @escaping ([SystemOverflowButton]) -> Void) {
        let maxY = primaryScreenMaxY()
        queue.async {
            let buttons = self.read(primaryScreenMaxY: maxY)
            DispatchQueue.main.async { completion(buttons) }
        }
    }

    static func menuBarAgentRoot() -> SystemOverflowNode? {
        guard let agent = NSRunningApplication.runningApplications(withBundleIdentifier: agentBundleIdentifier).first else { return nil }
        let element = AXUIElementCreateApplication(agent.processIdentifier)
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
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
        return children.map { child in
            AXUIElementSetMessagingTimeout(child, SystemOverflowIndicator.messagingTimeout)
            return AccessibilityNode(element: child)
        }
    }
}

#endif
