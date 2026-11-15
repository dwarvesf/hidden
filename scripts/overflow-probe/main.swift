//
//  main.swift
//  overflow-probe
//
//  Measures how macOS draws the menu bar overflow « for status items. Compiled by
//  run.sh together with the app's own SystemOverflowIndicator.swift, so the
//  classification here is the one Hidden Bar ships. See README.md.
//

import AppKit
import ApplicationServices
import CoreGraphics

struct Options {
    var count = 30
    var outPath: String?
    var notchMode = false
    var notchWidth: Int?
    var settle = 3.0
}

let usage = """
usage: overflow-probe [--count N] [--out FILE] [--settle SECONDS] [--notch-mode [--notch-width POINTS]]
  --count N          status items to create, titled P0.. (default 30)
  --out FILE         also write the report to FILE
  --settle SECONDS   wait for menu bar layout before reading (default 3)
  --notch-mode       switch the main display to the same-width HiDPI mode that includes the notch
                     (macOS restores the mode when the probe exits)
  --notch-width PTS  with --notch-mode: pick the taller mode of this point width (for example 1280)
                     instead of the current mode's pixel width
exit: 0 ok, 1 classification disagrees with an item's own window state, 3 Accessibility not trusted
"""

func parseOptions() -> Options {
    var options = Options()
    var args = Array(CommandLine.arguments.dropFirst())
    func next(_ flag: String) -> String {
        guard !args.isEmpty else {
            FileHandle.standardError.write(Data("missing value for \(flag)\n\(usage)\n".utf8))
            exit(64)
        }
        return args.removeFirst()
    }
    while !args.isEmpty {
        let flag = args.removeFirst()
        switch flag {
        case "--count": options.count = Int(next(flag)) ?? options.count
        case "--out": options.outPath = next(flag)
        case "--settle": options.settle = Double(next(flag)) ?? options.settle
        case "--notch-mode": options.notchMode = true
        case "--notch-width": options.notchWidth = Int(next(flag))
        case "-h", "--help":
            print(usage)
            exit(0)
        default:
            FileHandle.standardError.write(Data("unknown argument \(flag)\n\(usage)\n".utf8))
            exit(64)
        }
    }
    return options
}

let options = parseOptions()
var outHandle: FileHandle?

func emit(_ line: String = "") {
    print(line)
    fflush(stdout)
    outHandle?.write(Data((line + "\n").utf8))
}

func openOutFile(_ path: String) {
    let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: url.path, contents: nil)
    outHandle = FileHandle(forWritingAtPath: url.path)
}

func rect(_ r: CGRect) -> String {
    String(format: "(%.0f,%.0f %.0fx%.0f)", r.minX, r.minY, r.width, r.height)
}

func modeText(_ m: CGDisplayMode) -> String {
    "\(m.width)x\(m.height) pt, \(m.pixelWidth)x\(m.pixelHeight) px"
}

// auxiliaryTop*Area is documented in screen space; fold a display-local rect into
// global Cocoa coordinates when it is not already there.
func globalArea(_ area: NSRect?, on screen: NSScreen) -> NSRect? {
    guard let area = area, !area.isEmpty else { return nil }
    let frame = screen.frame
    if area.minX >= frame.minX - 0.5 && area.maxX <= frame.maxX + 0.5 { return area }
    return area.offsetBy(dx: frame.minX, dy: frame.minY)
}

// The notch is the gap between the two auxiliary areas.
func notchGap(of screen: NSScreen) -> ClosedRange<CGFloat>? {
    guard let left = globalArea(screen.auxiliaryTopLeftArea, on: screen),
          let right = globalArea(screen.auxiliaryTopRightArea, on: screen),
          right.minX > left.maxX else { return nil }
    return left.maxX...right.minX
}

// Notched Macs list each scaled resolution twice, with and without the notch band,
// at the same pixel width and different heights. Pick the taller one.
func switchToNotchMode() {
    let id = CGMainDisplayID()
    guard let current = CGDisplayCopyDisplayMode(id) else {
        emit("notch-mode: no current display mode, not switching")
        return
    }
    let listOptions = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
    let modes = (CGDisplayCopyAllDisplayModes(id, listOptions) as? [CGDisplayMode]) ?? []
    let candidates = modes.filter { mode in
        guard mode.isUsableForDesktopGUI(), mode.pixelWidth > mode.width else { return false }
        if let width = options.notchWidth { return mode.width == width }
        return mode.pixelWidth == current.pixelWidth
    }
    guard let target = candidates.max(by: { $0.pixelHeight < $1.pixelHeight }) else {
        emit("notch-mode: no HiDPI mode matches, staying in \(modeText(current))")
        return
    }
    if target.ioDisplayModeID == current.ioDisplayModeID {
        emit("notch-mode: already in the tallest matching mode \(modeText(current))")
        return
    }
    var config: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&config) == .success, let cfg = config else {
        emit("notch-mode: CGBeginDisplayConfiguration failed")
        return
    }
    CGConfigureDisplayWithDisplayMode(cfg, id, target, nil)
    let result = CGCompleteDisplayConfiguration(cfg, .forAppOnly)
    emit("notch-mode: \(modeText(current)) -> \(modeText(target)) (\(result == .success ? "app only, restored on exit" : "failed \(result.rawValue)"))")
}

let hiddenBarBundleIdentifier = "com.dwarvesv.minimalbar"

func screenName(_ screen: NSScreen?) -> String {
    screen?.localizedName ?? "nil"
}

func report(items: [NSStatusItem]) -> Int32 {
    let trusted = AXIsProcessTrusted()
    let indicator = SystemOverflowIndicator()
    let buttons = indicator.buttons
    let screens = NSScreen.screens

    emit("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
    emit("accessibility trusted: \(trusted)\(trusted ? "" : "  (the « cannot be read; grant this app in System Settings > Privacy & Security > Accessibility)")")
    // Hidden Bar hides other apps' items natively on macOS 27; items it hides have no
    // bar position, which would be read here as "unplaced", not as overflow.
    for app in NSRunningApplication.runningApplications(withBundleIdentifier: hiddenBarBundleIdentifier) {
        emit("WARNING: Hidden Bar is running (pid \(app.processIdentifier)); it can hide the probe's items. Quit it for a clean measurement.")
    }
    emit()
    emit("screens: \(screens.count)")
    for (index, screen) in screens.enumerated() {
        let left = globalArea(screen.auxiliaryTopLeftArea, on: screen).map(rect) ?? "none"
        let right = globalArea(screen.auxiliaryTopRightArea, on: screen).map(rect) ?? "none"
        let gap = notchGap(of: screen).map { String(format: "notch x %.0f..%.0f", $0.lowerBound, $0.upperBound) } ?? "no notch"
        emit("  [\(index)] \(screen.localizedName) frame=\(rect(screen.frame)) safeAreaTop=\(String(format: "%.0f", screen.safeAreaInsets.top)) auxLeft=\(left) auxRight=\(right) \(gap)")
    }
    emit()
    emit("« buttons: \(buttons.count)")
    for (index, button) in buttons.enumerated() {
        let frame = button.frame
        let owner = frame.flatMap { f in screens.first { $0.frame.contains(CGPoint(x: f.midX, y: f.midY)) } }
        emit("  [\(index)] \(button.state) frame=\(frame.map(rect) ?? "unreadable") display=\(screenName(owner))")
    }
    emit()
    emit("items: \(items.count)   (name: window frame | visible | screen | placement)")

    var onBar: [Int] = []
    var inOverflow: [Int] = []
    var behindNotch: [Int] = []
    var unplaced: [Int] = []
    var disagreements: [Int] = []

    for (index, item) in items.enumerated() {
        let window = item.button?.window
        let frame = window?.frame ?? .zero
        let screen = window?.screen
        let visible = window?.occlusionState.contains(.visible) ?? false
        let overflowed = SystemOverflowMatcher.isItemInSystemOverflow(
            windowFrame: frame, hasScreen: screen != nil, occlusionVisible: visible, indicators: buttons)

        // What the item's own window says, without the « geometry. A window on a screen
        // with zero height was never given a bar position (the bar is not laying
        // items out, or something hides them): neither on the bar nor in «.
        let isUnplaced = screen != nil && frame.height == 0 && !visible
        let ownSaysOverflow = screen == nil || !visible
        if !isUnplaced && overflowed != ownSaysOverflow { disagreements.append(index) }

        var place = "bar"
        if isUnplaced {
            place = "unplaced"
            unplaced.append(index)
        } else if overflowed {
            place = "in «"
            if screen == nil {
                place += " parked"
            } else {
                let slack = SystemOverflowMatcher.slack
                let centre = CGPoint(x: frame.midX, y: frame.midY)
                if let under = buttons.firstIndex(where: { $0.frame?.insetBy(dx: -slack, dy: -slack).contains(centre) == true }) {
                    place += " under «[\(under)]"
                }
            }
            inOverflow.append(index)
        } else if let screen = screen, let gap = notchGap(of: screen), gap.contains(frame.midX),
                  frame.midY > screen.frame.maxY - max(screen.safeAreaInsets.top, 1) {
            place = "behind notch"
            behindNotch.append(index)
        } else {
            onBar.append(index)
        }
        let agrees = isUnplaced || overflowed == ownSaysOverflow
        let flag = agrees ? "" : "  MISMATCH(own window says \(ownSaysOverflow ? "overflow" : "on bar"))"
        emit("  P\(index): \(rect(frame)) | visible=\(visible) | \(screenName(screen)) | \(place)\(flag)")
    }

    func names(_ indices: [Int]) -> String { indices.isEmpty ? "-" : indices.map { "P\($0)" }.joined(separator: " ") }
    emit()
    emit("on bar:  \(names(onBar))")
    emit("in «:    \(names(inOverflow))")
    emit("notch:   \(names(behindNotch))")
    if !unplaced.isEmpty { emit("unplaced: \(names(unplaced))") }
    let placed = items.count - unplaced.count
    emit("classification vs own window state: \(placed - disagreements.count)/\(placed) placed items agree\(disagreements.isEmpty ? "" : ", mismatches: \(names(disagreements))")")
    emit()
    emit("on bar \(onBar.count), in « \(inOverflow.count), behind notch \(behindNotch.count)\(unplaced.isEmpty ? "" : ", unplaced \(unplaced.count)")")

    if !trusted { return 3 }
    return disagreements.isEmpty ? 0 : 1
}

func runProbe() {
    if let path = options.outPath { openOutFile(path) }
    if options.notchMode { switchToNotchMode() }
    let layoutDelay = options.notchMode ? 1.5 : 0.0

    DispatchQueue.main.asyncAfter(deadline: .now() + layoutDelay) {
        var items: [NSStatusItem] = []
        for index in 0..<options.count {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.title = "P\(index)"
            items.append(item)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + options.settle) {
            let status = report(items: items)
            for item in items { NSStatusBar.system.removeStatusItem(item) }
            items.removeAll()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                try? outHandle?.close()
                exit(status)
            }
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
DispatchQueue.main.async { runProbe() }
app.run()
