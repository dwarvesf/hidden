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
    func press() -> Bool
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

    // Accessibility frames are top-left based and global; AppKit's are bottom-left,
    // flipped about the top edge of the screen that holds the menu bar origin.
    static func cocoaFrame(fromAccessibilityFrame frame: CGRect, primaryScreenMaxY: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryScreenMaxY - frame.minY - frame.height,
               width: frame.width, height: frame.height)
    }

    // The « of the display the window is on: the display it overlaps most, else the
    // fallback (an item parked off screen has no display).
    static func buttonIndex(forWindowFrame windowFrame: CGRect?,
                            displays: [CGRect],
                            fallbackDisplay: CGRect?,
                            buttons: [SystemOverflowButton]) -> Int? {
        var display = fallbackDisplay
        if let windowFrame = windowFrame {
            var bestArea: CGFloat = 0
            for candidate in displays {
                let overlap = candidate.intersection(windowFrame)
                let area = overlap.isNull ? 0 : overlap.width * overlap.height
                if area > bestArea {
                    bestArea = area
                    display = candidate
                }
            }
        }
        guard let display = display else { return nil }
        return buttons.firstIndex { button in
            guard let frame = button.frame else { return false }
            return display.contains(CGPoint(x: frame.midX, y: frame.midY))
        }
    }

    // An item macOS moved into « is either parked off screen at (0, -30) with no
    // screen, or stacked on a « with its window not visible. Occlusion alone is
    // not enough (an auto-hidden menu bar also clears it), so a « must exist and
    // the item must sit on one. Frames are all Cocoa.
    static func isItemInSystemOverflow(windowFrame: CGRect,
                                       hasScreen: Bool,
                                       occlusionVisible: Bool,
                                       indicators: [SystemOverflowButton]) -> Bool {
        guard !indicators.isEmpty else { return false }
        if !hasScreen && abs(windowFrame.minX) < 1 && abs(windowFrame.minY + 30) < 1 { return true }
        guard !occlusionVisible else { return false }
        return indicators.contains { button in
            guard let frame = button.frame else { return false }
            return windowFrame.intersects(frame.insetBy(dx: -slack, dy: -slack))
        }
    }
}

final class SystemOverflowIndicator {
    static let agentBundleIdentifier = "com.apple.MenuBarAgent"

    private let root: () -> SystemOverflowNode?
    private let primaryScreenMaxY: () -> CGFloat?
    private let displays: () -> [CGRect]
    private let mainDisplay: () -> CGRect?

    init(root: @escaping () -> SystemOverflowNode? = SystemOverflowIndicator.menuBarAgentRoot,
         primaryScreenMaxY: @escaping () -> CGFloat? = { NSScreen.screens.first?.frame.maxY },
         displays: @escaping () -> [CGRect] = { NSScreen.screens.map { $0.frame } },
         mainDisplay: @escaping () -> CGRect? = { NSScreen.main?.frame }) {
        self.root = root
        self.primaryScreenMaxY = primaryScreenMaxY
        self.displays = displays
        self.mainDisplay = mainDisplay
    }

    private func read() -> [(node: SystemOverflowNode, button: SystemOverflowButton)] {
        guard let root = root() else { return [] }
        let maxY = primaryScreenMaxY()
        return SystemOverflowMatcher.findAll(in: root).map { found in
            let frame = found.node.frame.flatMap { axFrame in
                maxY.map { SystemOverflowMatcher.cocoaFrame(fromAccessibilityFrame: axFrame, primaryScreenMaxY: $0) }
            }
            return (found.node, SystemOverflowButton(state: found.state, frame: frame))
        }
    }

    /// Every « on the bar, one per display that overflows. Empty when none.
    var buttons: [SystemOverflowButton] { read().map { $0.button } }

    var state: SystemOverflowState {
        let states = buttons.map { $0.state }
        if states.contains(.open) { return .open }
        return states.isEmpty ? .absent : .closed
    }

    /// Opens the « on the display the window is on (the main display when the
    /// window is parked), or closes it when open. False when that display has none.
    @discardableResult
    func press(onDisplayOf windowFrame: CGRect?) -> Bool {
        let found = read()
        guard let index = SystemOverflowMatcher.buttonIndex(forWindowFrame: windowFrame,
                                                            displays: displays(),
                                                            fallbackDisplay: mainDisplay(),
                                                            buttons: found.map { $0.button }) else { return false }
        return found[index].node.press()
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
