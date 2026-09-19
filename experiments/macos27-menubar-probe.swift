// macos27-menubar-probe.swift
//
// EXPERIMENTAL diagnostic — NOT part of the Hidden Bar app target, NOT shipped.
// Characterizes the macOS 27 ("Golden Gate") menu bar so a future hide mechanism
// can be designed (#360 / managed-overflow epic #366). It only READS state; it
// does not move, hide, or modify anything.
//
// Build & run (standalone, non-sandboxed so Accessibility can be granted):
//   swiftc experiments/macos27-menubar-probe.swift -o /tmp/mbprobe
//   /tmp/mbprobe
//
// Background: on macOS <= 26 each menu-bar status item was its own small CGWindow,
// and Hidden Bar hid neighbours by inflating its separator so they were pushed
// off-screen. On macOS 27 that no longer works (see #360 / PR #370). This probe
// gathers the signals a real macOS-27 hide path would need: who owns the bar now,
// what Accessibility still exposes, and how the status-layer windows look.

import AppKit
import ApplicationServices

func line(_ s: String) { print(s) }

// MARK: - 1. Accessibility trust

line("=== Accessibility ===")
line("AXIsProcessTrusted: \(AXIsProcessTrusted())")

// MARK: - 2. Menu-bar owning processes

let menuBarOwners = ["MenuBarAgent", "ControlCenter", "SystemUIServer", "WindowServer", "Window Server"]
let running = NSWorkspace.shared.runningApplications
    .compactMap { $0.localizedName }
line("\n=== Candidate menu-bar processes running ===")
for name in menuBarOwners where running.contains(name) {
    line("  running: \(name)")
}

// MARK: - 3. Public CGWindowList: the status-layer window landscape
//
// Reads geometry/owner only (no titles, no images) so it needs NO screen-recording
// permission. The macOS-26 model showed many small per-item windows here; the macOS-27
// consolidation should show very few (often one) menu-bar window per owner.

line("\n=== CGWindowList (on-screen) menu-bar / status windows ===")
let statusLevel = CGWindowLevelForKey(.statusWindow)        // NSStatusWindowLevel, ~25
let mainMenuLevel = CGWindowLevelForKey(.mainMenuWindow)
line("statusWindow level=\(statusLevel)  mainMenu level=\(mainMenuLevel)")

if let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
    var perOwner: [String: Int] = [:]
    var rows: [String] = []
    for w in infoList {
        let layer = (w[kCGWindowLayer as String] as? Int) ?? 0
        let owner = (w[kCGWindowOwnerName as String] as? String) ?? "?"
        let ownerPID = (w[kCGWindowOwnerPID as String] as? Int) ?? -1
        let b = (w[kCGWindowBounds as String] as? [String: CGFloat]) ?? [:]
        let y = b["Y"] ?? -1, h = b["Height"] ?? -1
        // The menu bar lives at the very top, ~24-40pt tall.
        let inMenuBarBand = (y >= 0 && y <= 8 && h > 0 && h <= 64)
        let atStatusLayer = (layer == Int(statusLevel) || layer == Int(mainMenuLevel))
        if inMenuBarBand || atStatusLayer {
            perOwner[owner, default: 0] += 1
            rows.append(String(format: "  layer=%4d owner=%@ pid=%d  x=%.0f y=%.0f w=%.0f h=%.0f",
                               layer, owner, ownerPID, b["X"] ?? -1, y, b["Width"] ?? -1, h))
        }
    }
    line("menu-bar/status windows by owner: \(perOwner.sorted { $0.value > $1.value })")
    line("rows (\(rows.count)):")
    rows.prefix(60).forEach { line($0) }
} else {
    line("  CGWindowListCopyWindowInfo returned nil")
}

// MARK: - 4. Accessibility: what the new menu bar exposes
//
// On macOS <= 26 the status extras were reachable as AXExtrasMenuBar / per-process
// menu bar 2. Probe whether macOS 27 still exposes them and via which element.

line("\n=== Accessibility: AXExtrasMenuBar probe ===")
func axChildrenSummary(_ element: AXUIElement, label: String) {
    var roleRef: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
    var childrenRef: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
    let children = (childrenRef as? [AXUIElement]) ?? []
    line("  \(label): role=\(roleRef as? String ?? "?") childrenErr=\(err.rawValue) childCount=\(children.count)")
    for (i, child) in children.prefix(20).enumerated() {
        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(child, kAXTitleAttribute as CFString, &titleRef)
        var posRef: CFTypeRef?
        AXUIElementCopyAttributeValue(child, kAXPositionAttribute as CFString, &posRef)
        var pos = CGPoint.zero
        if let posRef { AXValueGetValue(posRef as! AXValue, .cgPoint, &pos) }
        line("    [\(i)] title=\(titleRef as? String ?? "-") pos=(\(Int(pos.x)),\(Int(pos.y)))")
    }
}

// Dump the operations a hide mechanism would need: which attributes/actions a
// status item exposes, and whether its position is settable (= reorder/hide lever).
func dumpItemCapabilities(_ item: AXUIElement) {
    var attrNames: CFArray?
    AXUIElementCopyAttributeNames(item, &attrNames)
    var actionNames: CFArray?
    AXUIElementCopyActionNames(item, &actionNames)
    var settable: DarwinBoolean = false
    AXUIElementIsAttributeSettable(item, kAXPositionAttribute as CFString, &settable)
    var roleRef: CFTypeRef?, subroleRef: CFTypeRef?
    AXUIElementCopyAttributeValue(item, kAXRoleAttribute as CFString, &roleRef)
    AXUIElementCopyAttributeValue(item, kAXSubroleAttribute as CFString, &subroleRef)
    line("    first-item role=\(roleRef as? String ?? "?") subrole=\(subroleRef as? String ?? "?") positionSettable=\(settable.boolValue)")
    line("    attributes=\((attrNames as? [String]) ?? [])")
    line("    actions=\((actionNames as? [String]) ?? [])")
}

for app in NSWorkspace.shared.runningApplications where menuBarOwners.contains(app.localizedName ?? "") {
    let pid = app.processIdentifier
    let axApp = AXUIElementCreateApplication(pid)
    line("\n  -- \(app.localizedName ?? "?") (pid \(pid)) --")
    var extrasRef: CFTypeRef?
    let extrasErr = AXUIElementCopyAttributeValue(axApp, "AXExtrasMenuBar" as CFString, &extrasRef)
    if extrasErr == .success, let extras = extrasRef, CFGetTypeID(extras) == AXUIElementGetTypeID() {
        let extrasElement = extras as! AXUIElement
        axChildrenSummary(extrasElement, label: "AXExtrasMenuBar")
        var childrenRef: CFTypeRef?
        AXUIElementCopyAttributeValue(extrasElement, kAXChildrenAttribute as CFString, &childrenRef)
        if let first = (childrenRef as? [AXUIElement])?.first {
            dumpItemCapabilities(first)
        }
    } else {
        line("    AXExtrasMenuBar: err=\(extrasErr.rawValue)")
    }
    axChildrenSummary(axApp, label: "app root")
}

line("\n=== done ===")
