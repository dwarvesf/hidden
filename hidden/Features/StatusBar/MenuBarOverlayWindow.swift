//
//  MenuBarOverlayWindow.swift
//  Hidden Bar
//
//  Created for ultra-wide monitor support.
//  Covers menu bar items that macOS won't push off-screen.
//

import AppKit

class MenuBarOverlayWindow: NSPanel {

    override var canBecomeKey: Bool { return false }
    override var canBecomeMain: Bool { return false }

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        // Window configuration: sit just above status items so we cover them.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        ignoresMouseEvents = false  // Block clicks on covered items when collapsed
        isReleasedWhenClosed = false
    }

    /// Show the overlay covering the specified frame in screen coordinates.
    func showOverlay(frame: NSRect) {
        guard frame.width > 1 && frame.height > 0 else {
            hideOverlay()
            return
        }
        setFrame(frame, display: true)
        orderFrontRegardless()
    }

    /// Hide the overlay.
    func hideOverlay() {
        orderOut(nil)
    }
}
