//
//  NotchOverflowController.swift
//  Hidden Bar
//
//  Created by Nadir on 2026/03/30.
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import AppKit
import ApplicationServices

// MARK: - Menu Bar Extra Info

struct MenuBarExtraInfo {
  let element: AXUIElement
  let appName: String
  let appIcon: NSImage?
  let title: String?
  let pid: pid_t
  let position: CGPoint
  let size: CGSize
}

// MARK: - NotchOverflowController

class NotchOverflowController: NSObject {

  // MARK: - Properties

  /// Right edge of the notch in screen X coordinates
  private var notchRightEdge: CGFloat {
    guard let screen = NSScreen.main else { return 972 }
    let notchWidth = screen.frame.width / 8
    return screen.frame.width / 2 + notchWidth / 2
  }

  // MARK: - Notch Detection

  static var hasNotch: Bool {
    if #available(macOS 12.0, *) {
      guard let screen = NSScreen.main else { return false }
      return screen.safeAreaInsets.top > 0
    }
    return false
  }

  // MARK: - Setup

  func setup() {
    // No-op; hotkey is set up in AppDelegate
  }

  func teardown() {
    // No-op
  }

  // MARK: - Public: called from hotkey handler
  func triggerOverflow() {
    showOverflowMenuAtCursor()
  }

  /// Show overflow menu anchored to a status item (called from StatusBarController)
  func showOverflowMenuFromSeparator(near item: NSStatusItem) {
    guard ensureAccessibility() else { return }
    let menu = buildOverflowMenu()
    item.menu = menu
    item.button?.performClick(nil)
    DispatchQueue.main.async {
      item.menu = nil
    }
  }

  // MARK: - Show Menu at Cursor

  private func showOverflowMenuAtCursor() {
    guard ensureAccessibility() else { return }

    let menu = buildOverflowMenu()
    let mouseLocation = NSEvent.mouseLocation

    // Create a temporary invisible window at mouse location to anchor the menu
    let tmpWindow = NSWindow(
      contentRect: NSRect(x: mouseLocation.x - 1, y: mouseLocation.y - 1, width: 2, height: 2),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    tmpWindow.level = .popUpMenu
    tmpWindow.backgroundColor = .clear
    tmpWindow.isOpaque = false
    tmpWindow.orderFrontRegardless()

    menu.popUp(positioning: nil, at: NSPoint(x: 1, y: 1), in: tmpWindow.contentView)

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      tmpWindow.orderOut(nil)
    }
  }

  // MARK: - Menu Building

  private func buildOverflowMenu() -> NSMenu {
    let allExtras = getAllMenuBarExtras()

    let rightEdge = notchRightEdge
    let hiddenExtras = allExtras.filter {
      $0.size.width > 0 && $0.size.height > 0 && $0.position.x < rightEdge
    }
    let visibleExtras = allExtras.filter {
      $0.size.width > 0 && $0.size.height > 0 && $0.position.x >= rightEdge
    }

    let menu = NSMenu()
    menu.autoenablesItems = false

    // Title
    let titleItem = NSMenuItem(title: "Notch Overflow  \u{2318}\u{21E7}B", action: nil, keyEquivalent: "")
    titleItem.isEnabled = false
    if #available(macOS 10.14, *) {
      titleItem.attributedTitle = NSAttributedString(
        string: titleItem.title,
        attributes: [
          .font: NSFont.systemFont(ofSize: 12, weight: .bold),
          .foregroundColor: NSColor.secondaryLabelColor
        ])
    }
    menu.addItem(titleItem)
    menu.addItem(NSMenuItem.separator())

    // Hidden section
    if !hiddenExtras.isEmpty {
      let header = NSMenuItem(
        title: "\u{26A0} Hidden Behind Notch (\(hiddenExtras.count))",
        action: nil, keyEquivalent: "")
      header.isEnabled = false
      menu.addItem(header)
      menu.addItem(NSMenuItem.separator())

      for info in hiddenExtras.sorted(by: { $0.position.x > $1.position.x }) {
        menu.addItem(makeMenuItem(for: info, hidden: true))
      }
    }

    // Visible section
    if !visibleExtras.isEmpty {
      if !hiddenExtras.isEmpty { menu.addItem(NSMenuItem.separator()) }
      let header = NSMenuItem(
        title: "Visible (\(visibleExtras.count))",
        action: nil, keyEquivalent: "")
      header.isEnabled = false
      menu.addItem(header)
      menu.addItem(NSMenuItem.separator())

      for info in visibleExtras.sorted(by: { $0.position.x > $1.position.x }) {
        menu.addItem(makeMenuItem(for: info, hidden: false))
      }
    }

    // Empty state
    if hiddenExtras.isEmpty && visibleExtras.isEmpty {
      let emptyItem = NSMenuItem(
        title: "No items found (grant Accessibility permission)",
        action: nil, keyEquivalent: "")
      emptyItem.isEnabled = false
      menu.addItem(emptyItem)
    }

    return menu
  }

  private func makeMenuItem(for info: MenuBarExtraInfo, hidden: Bool = false) -> NSMenuItem {
    let item = NSMenuItem()
    let displayTitle = (info.title?.isEmpty == false) ? info.title! : info.appName

    if hidden {
      if #available(macOS 10.14, *) {
        item.attributedTitle = NSAttributedString(
          string: displayTitle,
          attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.systemOrange
          ])
      } else {
        item.title = displayTitle
      }
    } else {
      item.title = displayTitle
    }

    if let icon = info.appIcon {
      item.image = hidden ? icon.resizedForMenu(tinted: true) : icon.resizedForMenu()
    }
    item.representedObject = info
    item.target = self
    item.action = #selector(activateItem(_:))
    return item
  }

  @objc private func activateItem(_ sender: NSMenuItem) {
    guard let info = sender.representedObject as? MenuBarExtraInfo else { return }
    AXUIElementPerformAction(info.element, kAXPressAction as CFString)
  }

  // MARK: - Accessibility

  private func ensureAccessibility() -> Bool {
    if AXIsProcessTrusted() { return true }
    let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
    AXIsProcessTrustedWithOptions(opts)
    return false
  }

  // MARK: - AX Enumeration

  private func getAllMenuBarExtras() -> [MenuBarExtraInfo] {
    var results: [MenuBarExtraInfo] = []
    let myPID = ProcessInfo.processInfo.processIdentifier

    for app in NSWorkspace.shared.runningApplications {
      if app.processIdentifier == myPID { continue }

      let axApp = AXUIElementCreateApplication(app.processIdentifier)
      var extrasRef: AnyObject?
      let err = AXUIElementCopyAttributeValue(
        axApp, "AXExtrasMenuBar" as CFString, &extrasRef)
      guard err == .success else { continue }

      var childrenRef: AnyObject?
      let childErr = AXUIElementCopyAttributeValue(
        extrasRef as! AXUIElement,
        kAXChildrenAttribute as CFString, &childrenRef)
      guard childErr == .success,
        let children = childrenRef as? [AXUIElement]
      else { continue }

      for child in children {
        var titleRef: AnyObject?
        AXUIElementCopyAttributeValue(child, kAXTitleAttribute as CFString, &titleRef)

        var posRef: AnyObject?
        AXUIElementCopyAttributeValue(child, kAXPositionAttribute as CFString, &posRef)
        var pos = CGPoint.zero
        if let pv = posRef { AXValueGetValue(pv as! AXValue, .cgPoint, &pos) }

        var sizeRef: AnyObject?
        AXUIElementCopyAttributeValue(child, kAXSizeAttribute as CFString, &sizeRef)
        var size = CGSize.zero
        if let sv = sizeRef { AXValueGetValue(sv as! AXValue, .cgSize, &size) }

        results.append(MenuBarExtraInfo(
          element: child,
          appName: app.localizedName ?? "Unknown",
          appIcon: app.icon,
          title: titleRef as? String,
          pid: app.processIdentifier,
          position: pos,
          size: size
        ))
      }
    }
    return results
  }

}

// MARK: - NSImage Extension

private extension NSImage {
  func resizedForMenu(tinted: Bool = false) -> NSImage {
    let target = NSSize(width: 18, height: 18)
    let img = NSImage(size: target)
    img.lockFocus()
    self.draw(in: NSRect(origin: .zero, size: target),
              from: NSRect(origin: .zero, size: self.size),
              operation: .sourceOver, fraction: tinted ? 0.5 : 1.0)
    img.unlockFocus()
    return img
  }
}
