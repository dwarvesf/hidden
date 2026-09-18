//
//  StatusBarController.swift
//  vanillaClone
//
//  Created by Thanh Nguyen on 1/30/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import AppKit
import ApplicationServices
import Darwin

// Assessment mode can express the policy as bundle identifiers and a small set
// of Apple menu-item identifiers, but it cannot read Hidden Bar's dividers.
// Accessibility supplies the missing layout snapshot while the bar is expanded.
// The snapshot is deliberately best-effort: a denied or incomplete tree falls
// back to Hidden Bar's original "hide third-party items" policy.
private struct MenuBarLayoutSnapshot {
    let allowedBundleIdentifiers: [String]
    let allowedSystemItems: [Int]

    static let allSystemItems = Array(0...63)
}

private final class MenuBarLayoutReader {
    private struct Item {
        let midX: CGFloat
        let bundleIdentifier: String?
        let systemItem: Int?
    }

    func snapshot(separatorX: CGFloat) -> MenuBarLayoutSnapshot? {
        // Ask macOS to show its standard consent prompt when this build has
        // not yet been granted Accessibility access. Without it, there is no
        // supported way to recover a user's custom divider layout.
        let trustOptions = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(trustOptions),
              separatorX.isFinite,
              let agent = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.MenuBarAgent").first else {
            return nil
        }

        let root = AXUIElementCreateApplication(agent.processIdentifier)
        guard let windows: [AXUIElement] = attribute(kAXWindowsAttribute as CFString, from: root) else { return nil }
        // A menu-bar window contains the divider's x coordinate. This chooses
        // the correct AX window even when a second display has a different
        // origin or scale.
        // MenuBarAgent returns one AX window per display/space. A single
        // window can briefly be stale during a display change, so merge every
        // window containing the divider rather than trusting the first one.
        let matchingWindows = windows.filter {
            guard let frame = frame(of: $0) else { return false }
            return frame.minX <= separatorX && separatorX <= frame.maxX
        }
        let items = matchingWindows.flatMap { window in
            let groups: [AXUIElement] = attribute(kAXChildrenAttribute as CFString, from: window) ?? []
            return groups.compactMap(makeItem)
        }
        guard !items.isEmpty else { return nil }

        let ownBundle = Bundle.main.bundleIdentifier ?? "com.dwarvesv.minimalbar"
        let runningBundles = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        var hiddenBundles = Set<String>()
        var visibleBundles = Set<String>()
        var visibleSystemItems = Set<Int>()

        for item in items {
            let isVisible = Constant.isUsingLTRLanguage ? item.midX > separatorX : item.midX < separatorX
            if let bundle = item.bundleIdentifier, bundle != ownBundle {
                if isVisible {
                    visibleBundles.insert(bundle)
                } else {
                    hiddenBundles.insert(bundle)
                }
            }
            if isVisible, let system = item.systemItem {
                visibleSystemItems.insert(system)
            }
        }

        // A bundle appearing on both sides remains visible. This matches the
        // native policy's bundle granularity and avoids incorrectly hiding an
        // app with multiple menu-bar items.
        let leftOnly = hiddenBundles.subtracting(visibleBundles)
        let allowedBundles = Array(runningBundles.subtracting(leftOnly).union(visibleBundles).union([ownBundle])).sorted()
        // An empty system set is only valid when AX genuinely found no system
        // controls. In a partial tree we keep the system row intact.
        let allowedSystem = visibleSystemItems.isEmpty ? MenuBarLayoutSnapshot.allSystemItems : Array(visibleSystemItems).sorted()
        NSLog("Hidden Bar layout snapshot: visible bundles=%@, visible system items=%@", allowedBundles, allowedSystem)
        return MenuBarLayoutSnapshot(allowedBundleIdentifiers: allowedBundles, allowedSystemItems: allowedSystem)
    }

    private func makeItem(_ group: AXUIElement) -> Item? {
        guard let frame = frame(of: group), frame.width > 0 else { return nil }
        let children: [AXUIElement] = attribute(kAXChildrenAttribute as CFString, from: group) ?? []
        let bundle = bundleIdentifier(for: group) ?? children.compactMap(bundleIdentifier).first
        return Item(midX: frame.midX, bundleIdentifier: bundle, systemItem: bundle == nil ? systemItem(in: children) : nil)
    }

    private func systemItem(in children: [AXUIElement]) -> Int? {
        for child in children {
            if let result = systemItem(in: child) { return result }
        }
        return nil
    }

    private func systemItem(in element: AXUIElement) -> Int? {
        let values = [stringValue(of: element, attribute: kAXIdentifierAttribute as CFString), stringValue(of: element, attribute: kAXTitleAttribute as CFString), stringValue(of: element, attribute: kAXDescriptionAttribute as CFString)]
            .compactMap { $0 }.joined(separator: " ").lowercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: "")
        if values.contains("battery") { return 0 }
        if values.contains("bluetooth") { return 1 }
        if values.contains("clock") || values.contains("datetime") { return 2 }
        if values.contains("display") && !values.contains("mirroring") { return 3 }
        if values.contains("keyboard") || values.contains("textinput") || values.contains("inputmenu") { return 4 }
        if values.contains("volume") || values.contains("sound") { return 5 }
        if values.contains("wifi") || values.contains("airport") { return 6 }
        if values.contains("mirroring") { return 7 }
        if values.contains("controlcenter") || values.contains("bento") { return 8 }
        let children: [AXUIElement] = attribute(kAXChildrenAttribute as CFString, from: element) ?? []
        return systemItem(in: children)
    }

    private func bundleIdentifier(for element: AXUIElement) -> String? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success,
              let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
              bundle != "com.apple.MenuBarAgent" else { return nil }
        return bundle
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        guard let position: AXValue = attribute(kAXPositionAttribute as CFString, from: element),
              let size: AXValue = attribute(kAXSizeAttribute as CFString, from: element),
              AXValueGetType(position) == .cgPoint, AXValueGetType(size) == .cgSize else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &point), AXValueGetValue(size, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }

    private func stringValue(of element: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? String
    }

    private func attribute<T>(_ attribute: CFString, from element: AXUIElement) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? T
    }
}

// macOS 27's status-item widths are shared by every attached display.  Assessment
// mode is a policy applied by MenuBarAgent instead, so it hides third-party items
// without allocating a fake span on either menu bar.  The framework is private:
// resolve it at runtime and keep the established path as the fallback.
private final class MenuBarAssessmentMode {
    private let framework = "/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore"
    private let configure = NSSelectorFromString("initWithAllowedSystemItems:allowedBundleIdentifiers:")
    private let activate = NSSelectorFromString("activateWithConfiguration:completionHandler:")
    private let invalidate = NSSelectorFromString("invalidate")
    private var assertion: AnyObject?

    var isActive: Bool { assertion != nil }

    var isAvailable: Bool {
        guard #available(macOS 27.0, *) else { return false }
        guard dlopen(framework, RTLD_NOW | RTLD_LOCAL) != nil,
              let configuration = NSClassFromString("MBAssessmentModeConfiguration"),
              let candidate = NSClassFromString("MBAssessmentModeAssertion") else { return false }
        return configuration.instancesRespond(to: configure)
            && candidate.instancesRespond(to: activate)
            && candidate.instancesRespond(to: invalidate)
    }

    func hideItems(using snapshot: MenuBarLayoutSnapshot?) {
        guard isAvailable else { return }
        showAllItems()
        guard let configurationClass = NSClassFromString("MBAssessmentModeConfiguration"),
              let assertionClass = NSClassFromString("MBAssessmentModeAssertion") else { return }
        let systemItems = (snapshot?.allowedSystemItems ?? MenuBarLayoutSnapshot.allSystemItems)
            .map { NSNumber(value: $0) } as NSArray
        let ownBundle = Bundle.main.bundleIdentifier ?? "com.dwarvesv.minimalbar"
        let allowedBundles = snapshot?.allowedBundleIdentifiers ?? [ownBundle]
        guard let configuration = (configurationClass.alloc() as AnyObject)
            .perform(configure, with: systemItems, with: allowedBundles as NSArray)?
            .takeUnretainedValue(),
              let newAssertion = (assertionClass.alloc() as AnyObject)
                .perform(NSSelectorFromString("init"))?.takeUnretainedValue() else { return }
        let completion: @convention(block) (AnyObject?) -> Void = { error in
            if let error { NSLog("Hidden Bar assessment mode rejected: \(error)") }
        }
        _ = newAssertion.perform(activate, with: configuration, with: completion)
        assertion = newAssertion
    }

    func showAllItems() {
        guard let assertion else { return }
        _ = assertion.perform(invalidate)
        self.assertion = nil
    }
}

class StatusBarController {
    
    //MARK: - Variables
    private var timer:Timer? = nil
    private let assessmentMode = MenuBarAssessmentMode()
    private let layoutReader = MenuBarLayoutReader()
    
    //MARK: - BarItems

    // Created and named in declaration order on purpose: a status item registers
    // with the menu bar under its autosave name, and on macOS 27 every new name
    // lands left of the previous one, so the bar reads separator, spacers, arrow.
    private let btnExpandCollapse = StatusBarController.makeItem("hiddenbar_expandcollapse", length: NSStatusItem.variableLength)
    private let spacers: [NSStatusItem] = StatusBarController.makeSpacers()  // macOS 27 only, empty elsewhere
    private let btnSeparate = StatusBarController.makeItem("hiddenbar_separate", length: 1)
    private var btnAlwaysHidden:NSStatusItem? = nil
    
    private var btnHiddenLength: CGFloat = 20
    private var btnHiddenCollapseLength: CGFloat = 2000
    
    private var btnAlwaysHiddenLength: CGFloat = Preferences.alwaysHiddenSectionEnabled ? 20 : 0
    private var btnAlwaysHiddenEnableExpandCollapseLength: CGFloat = Preferences.alwaysHiddenSectionEnabled ? 2000 : 0
    
    private let imgIconLine = NSImage(named:NSImage.Name("ic_line"))
    
    private var isCollapsed: Bool {
        // Compare with > rather than == so the state survives updateCollapsedLengths
        // changing btnHiddenCollapseLength while the bar is collapsed (PR #354).
        return assessmentMode.isActive || self.btnSeparate.length > self.btnHiddenLength
    }
    
    private var isBtnSeparateValidPosition: Bool {
        guard
            let btnExpandCollapseX = self.btnExpandCollapse.button?.getOrigin?.x,
            let btnSeparateX = self.btnSeparate.button?.getOrigin?.x
            else {return false}
        
        if Constant.isUsingLTRLanguage {
            return btnExpandCollapseX >= btnSeparateX
        } else {
            return btnExpandCollapseX <= btnSeparateX
        }
    }
    
    private var isBtnAlwaysHiddenValidPosition: Bool {
        if !Preferences.alwaysHiddenSectionEnabled { return true }
        
        guard
            let btnSeparateX = self.btnSeparate.button?.getOrigin?.x,
            let btnAlwaysHiddenX = self.btnAlwaysHidden?.button?.getOrigin?.x
            else {return false}
        
        if Constant.isUsingLTRLanguage {
            return btnSeparateX >= btnAlwaysHiddenX
        } else {
            return btnSeparateX <= btnAlwaysHiddenX
        }
    }
    
    private var isToggle = false

    // macOS 27 keeps every item's position in its own layout table, keyed by
    // autosave name, and the app can neither read nor seed it. A new item always
    // lands leftmost. The spacers can therefore only end up between the arrow
    // and the separator if all three are registered fresh, in order, so on 27 the
    // items use new names. Upgraders drag their icons past the separator once,
    // as on a fresh install.
    private static let autosaveSuffix: String = {
        if #available(macOS 27.0, *) { return "_v27" }
        return ""
    }()

    // macOS 27 drops a status item whose length reaches half the display width
    // instead of clamping it (#360). Measured on 27.0: a 3008pt display keeps
    // 1480pt and drops 1500pt. One length is applied on every display's bar, so
    // the unit is sized under the NARROWEST display's cliff.
    @available(macOS 27.0, *)
    private static var collapseUnit: CGFloat {
        let narrowest = NSScreen.screens.map { $0.frame.width }.min() ?? 1728
        return max(200, (narrowest / 2 - 64).rounded(.down))
    }

    private static func makeItem(_ name: String, length: CGFloat) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: length)
        item.autosaveName = name + autosaveSuffix
        return item
    }

    // Below the cliff macOS 27 pushes the icons left of the separator into its
    // native overflow menu («), but only once they reach the frontmost app's
    // menus. One unit does not span that distance on wide displays, so the
    // separator gets company: zero-length items to its right that inflate with
    // it. macOS overflows from the left, so the icons go first and the spacers
    // stay; surplus spacers overflow themselves, which is harmless. The count
    // is fixed so every launch registers the same names: a name first seen on a
    // later launch would land leftmost, outside the block. Seven units cover a
    // 5800pt display next to an 1800pt one.
    private static func makeSpacers() -> [NSStatusItem] {
        guard #available(macOS 27.0, *) else { return [] }
        return (0..<6).map { index in
            let item = makeItem("hiddenbar_spacer\(index)", length: 0)
            item.button?.isEnabled = false
            item.isVisible = false
            return item
        }
    }

    // Spacers are visible only while collapsed. isVisible keeps the item's slot
    // in the layout table, so they come back between the arrow and the
    // separator and take no room in the expanded bar.
    private func setSpacersInflated(_ inflated: Bool) {
        for spacer in spacers {
            spacer.isVisible = inflated
            spacer.length = inflated ? btnHiddenCollapseLength : 0
        }
    }

    private var hoverMonitor: Any?
    private var hoverDwellTimer: Timer?

    // True while the pointer sits in any screen's menubar band (the strip between
    // visibleFrame.maxY and frame.maxY, which is the menubar's exact height there).
    // On fullscreen spaces the menubar is hidden and the band collapses to ~zero,
    // so this returns false there: intentional, no visible menubar = no deferral.
    private var isMouseInMenuBar: Bool {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.contains { screen in
            mouse.x >= screen.frame.minX && mouse.x <= screen.frame.maxX
                && mouse.y >= screen.visibleFrame.maxY && mouse.y <= screen.frame.maxY
        }
    }

    // The preferences window is an ordinary app window, not in the menu bar, so
    // the mouse-in-menubar guard does not cover it. With "use full menu bar on
    // expanding" on, an auto-collapse deactivates the app and dismisses this
    // window mid-edit (#170, same family as #66/#151). Defer the collapse while
    // it is on screen. isWindowLoaded short-circuits without force-loading the
    // window when preferences were never opened.
    private var isPreferencesWindowVisible: Bool {
        let wc = PreferencesWindowController.shared
        return wc.isWindowLoaded && (wc.window?.isVisible ?? false)
    }
    
    //MARK: - Methods
    init() {
        updateCollapsedLengths()
        setupUI()
        restoreRemovedStatusItems()
        setupAlwayHideStatusBar()
        setupHoverToExpandIfEnabled()
        NotificationCenter.default.addObserver(self, selector: #selector(handleScreenParametersChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.collapseMenuBarOnLaunch(attemptsLeft: 10)
        }
        
        if Preferences.areSeparatorsHidden {hideSeparators()}
        autoCollapseIfNeeded()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        hoverDwellTimer?.invalidate()
        if let monitor = hoverMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // Opt-in via `defaults write com.dwarvesv.minimalbar hoverToExpand -bool true`.
    // No monitor is installed at all unless the pref is true at launch.
    private func setupHoverToExpandIfEnabled() {
        guard Preferences.hoverToExpand else { return }
        NSLog("HoverToExpand: enabled, installing global mouse monitor")
        hoverMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            guard let self = self else { return }
            guard self.isCollapsed && self.isMouseInMenuBar else {
                self.hoverDwellTimer?.invalidate()
                self.hoverDwellTimer = nil
                return
            }
            // Short dwell so a pointer merely passing through doesn't expand.
            guard self.hoverDwellTimer == nil else { return }
            self.hoverDwellTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                self.hoverDwellTimer = nil
                if self.isCollapsed && self.isMouseInMenuBar {
                    self.expandMenubar()
                }
            }
        }
    }
    
    @objc private func handleScreenParametersChanged() {
        // Re-apply the recomputed length to the LIVE item when collapsed, or a
        // display hot-plug leaves the separator at a stale length (PR #354).
        let wasCollapsed = isCollapsed
        updateCollapsedLengths()
        if wasCollapsed {
            btnSeparate.length = btnHiddenCollapseLength
            setSpacersInflated(true)
            if Preferences.areSeparatorsHidden {
                btnAlwaysHidden?.length = btnAlwaysHiddenEnableExpandCollapseLength
            }
        }
    }

    private func updateCollapsedLengths() {
        let boundedCollapseLength: CGFloat
        if #available(macOS 27.0, *) {
            // See collapseUnit and makeSpacers: one unit per item, spacers make
            // up the rest of the span. Displaced icons go into the native
            // overflow menu rather than off-screen.
            boundedCollapseLength = StatusBarController.collapseUnit
        } else {
            // The menubar replicates across every attached display, so the collapse
            // length must cover the WIDEST screen, not NSScreen.main (the focused one);
            // sizing from a narrower screen leaks hidden icons on wider displays.
            // frame.width, not visibleFrame: the menubar spans the full frame width.
            let screenWidth = NSScreen.screens.map { $0.frame.width }.max() ?? 1728
            // Keep collapse length bounded to avoid pathological layout/memory behavior;
            // macOS enforces a hard 10,000pt maximum on NSStatusItem.length (PR #354).
            boundedCollapseLength = max(500, min(screenWidth * 2, 10_000))
        }
        btnHiddenCollapseLength = boundedCollapseLength
        btnAlwaysHiddenEnableExpandCollapseLength = Preferences.alwaysHiddenSectionEnabled ? boundedCollapseLength : 0
    }
    
    private func restoreRemovedStatusItems() {
        // Cmd-dragging a status item off the bar is persisted by macOS via
        // autosaveName, leaving the app running but unreachable. These items are
        // the app's only UI, so they self-restore at launch.
        btnExpandCollapse.isVisible = true
        btnSeparate.isVisible = true
    }

    private func setupUI() {
        if let button = btnSeparate.button {
            button.image = self.imgIconLine
        }
        let menu = self.getContextMenu()
        btnSeparate.menu = menu

        updateAutoCollapseMenuTitle()
        
        if let button = btnExpandCollapse.button {
            button.image = Assets.collapseImage
            button.target = self
            
            button.action = #selector(self.btnExpandCollapsePressed(sender:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }
    
    @objc func btnExpandCollapsePressed(sender: NSStatusBarButton) {
        if let event = NSApp.currentEvent {

            let isOptionKeyPressed = event.modifierFlags.contains(NSEvent.ModifierFlags.option)

            if event.type == NSEvent.EventType.leftMouseUp && !isOptionKeyPressed{
                self.expandCollapseIfNeeded()
            } else if event.type == NSEvent.EventType.rightMouseUp && !isOptionKeyPressed {
                // Right-click opens the same context menu the separator has (#356),
                // making settings reachable from the control everyone clicks.
                // The separators/always-hidden toggle stays on option-click.
                showContextMenu(from: sender)
            } else {
                // Both option+left and option+right land here: separators toggle.
                self.showHideSeparatorsAndAlwayHideArea()
            }
        }
    }

    private func showContextMenu(from button: NSStatusBarButton) {
        guard let menu = btnSeparate.menu else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 5), in: button)
    }
    
    func showHideSeparatorsAndAlwayHideArea() {
        Preferences.areSeparatorsHidden ? self.showSeparators() : self.hideSeparators()
        
        if self.isCollapsed {self.expandMenubar()}
    }
    
    private func showSeparators() {
        Preferences.areSeparatorsHidden = false
        
        if !self.isCollapsed {
            self.btnSeparate.length = self.btnHiddenLength
        }
        self.btnAlwaysHidden?.length = self.btnAlwaysHiddenLength
    }
    
    private func hideSeparators() {
        guard self.isBtnAlwaysHiddenValidPosition else {return}
        
        Preferences.areSeparatorsHidden = true
        
        if !self.isCollapsed {
            self.btnSeparate.length = self.btnHiddenLength
        }
        self.btnAlwaysHidden?.length = self.btnAlwaysHiddenEnableExpandCollapseLength
    }
    
    func expandCollapseIfNeeded() {
        //prevented rapid click cause icon show many in Dock
        if isToggle {return}
        isToggle = true
        self.isCollapsed ? self.expandMenubar() : self.collapseMenuBar()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.isToggle = false
        }
    }
    
    // macOS 27's shared menu-bar window may not have item frames for a beat
    // after launch, so the position guard would skip the first collapse.
    // Retry a few times; if the items were cmd-dragged out of order the guard
    // stays false and we stop, same as before.
    private func collapseMenuBarOnLaunch(attemptsLeft: Int) {
        if isBtnSeparateValidPosition || attemptsLeft <= 0 {
            collapseMenuBar()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.collapseMenuBarOnLaunch(attemptsLeft: attemptsLeft - 1)
        }
    }

    private func collapseMenuBar() {
        guard self.isBtnSeparateValidPosition && !self.isCollapsed else {
            autoCollapseIfNeeded()
            return
        }

        if assessmentMode.isAvailable {
            let separatorX = btnSeparate.button?.window?.convertToScreen(
                btnSeparate.button?.convert(btnSeparate.button?.bounds ?? .zero, to: nil) ?? .zero
            ).minX ?? btnSeparate.button?.getOrigin?.x ?? 0
            if let snapshot = layoutReader.snapshot(separatorX: separatorX) {
                btnSeparate.length = btnHiddenLength
                setSpacersInflated(false)
                assessmentMode.hideItems(using: snapshot)
                setSeparatorGlyphVisible(false)
            } else {
                // Never turn an unreadable layout into "hide every app".
                // The established spacer implementation preserves the user's
                // physical divider arrangement until a complete AX snapshot is
                // available.
                btnSeparate.length = self.btnHiddenCollapseLength
                setSpacersInflated(true)
                setSeparatorGlyphVisible(false)
            }
        } else {
            btnSeparate.length = self.btnHiddenCollapseLength
            setSpacersInflated(true)
            setSeparatorGlyphVisible(false)
        }
        if let button = btnExpandCollapse.button {
            button.image = Assets.expandImage
        }
        if Preferences.useFullStatusBarOnExpandEnabled {
            NSApp.setActivationPolicy(.accessory)
            NSApp.deactivate()
        }
    }
    private func expandMenubar() {
        guard self.isCollapsed else {return}
        assessmentMode.showAllItems()
        btnSeparate.length = btnHiddenLength
        setSpacersInflated(false)
        setSeparatorGlyphVisible(true)
        if let button = btnExpandCollapse.button {
            button.image = Assets.collapseImage
        }
        autoCollapseIfNeeded()
        
        if Preferences.useFullStatusBarOnExpandEnabled {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            
        }
    }
    
    private func autoCollapseIfNeeded() {
        guard Preferences.isAutoHide else {return}
        guard !isCollapsed else { return }

        startTimerToAutoHide()
    }

    // The button draws the "|" glyph centered in the item's span. On macOS <= 26
    // that span is off-screen while collapsed; on 27 it is on-screen, showing a
    // stray line mid-menu-bar (#360). Clicks still land on the item.
    private func setSeparatorGlyphVisible(_ visible: Bool) {
        guard #available(macOS 27.0, *) else { return }
        btnSeparate.button?.image = visible ? imgIconLine : nil
    }

    private func startTimerToAutoHide() {
        timer?.invalidate()
        self.timer = Timer.scheduledTimer(withTimeInterval: Preferences.numberOfSecondForAutoHide, repeats: false) { [weak self] _ in
            guard let self = self, Preferences.isAutoHide else { return }
            // Don't yank the bar shut mid-interaction: while the pointer is in the
            // menubar (hovering, clicking, dragging icons), defer and re-arm.
            // Intentionally unbounded; each re-arm invalidates the previous timer,
            // so deferral never accumulates timers.
            if self.isMouseInMenuBar || self.isPreferencesWindowVisible {
                self.startTimerToAutoHide()
            } else {
                self.collapseMenuBar()
            }
        }
    }
    
    private func getContextMenu() -> NSMenu {
        let menu = NSMenu()
        
        let prefItem = NSMenuItem(title: "Preferences...".localized, action: #selector(openPreferenceViewControllerIfNeeded), keyEquivalent: "P")
        prefItem.target = self
        menu.addItem(prefItem)
        
        let toggleAutoHideItem = NSMenuItem(title: "Toggle Auto Collapse".localized, action: #selector(toggleAutoHide), keyEquivalent: "t")
        toggleAutoHideItem.target = self
        toggleAutoHideItem.tag = 1
        NotificationCenter.default.addObserver(self, selector: #selector(updateAutoHide), name: .prefsChanged, object: nil)
        menu.addItem(toggleAutoHideItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit".localized, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        return menu
    }
    
    private func updateAutoCollapseMenuTitle() {
        guard let toggleAutoHideItem = btnSeparate.menu?.item(withTag: 1) else { return }
        if Preferences.isAutoHide {
            toggleAutoHideItem.title = "Disable Auto Collapse".localized
        } else {
            toggleAutoHideItem.title = "Enable Auto Collapse".localized
        }
    }
    
    @objc func updateAutoHide() {
        updateAutoCollapseMenuTitle()
        autoCollapseIfNeeded()
    }
    
    @objc func openPreferenceViewControllerIfNeeded() {
        Util.showPrefWindow()
    }
    
    @objc func toggleAutoHide() {
        Preferences.isAutoHide.toggle()
    }
}


//MARK: - Alway hide feature
extension StatusBarController {
    private func setupAlwayHideStatusBar() {
        NotificationCenter.default.addObserver(self, selector: #selector(toggleStatusBarIfNeeded), name: .alwayHideToggle, object: nil)
        toggleStatusBarIfNeeded()
    }
    @objc private func toggleStatusBarIfNeeded() {
        updateCollapsedLengths()

        if Preferences.alwaysHiddenSectionEnabled {
            if let existing = self.btnAlwaysHidden {
                NSStatusBar.system.removeStatusItem(existing)
            }
            self.btnAlwaysHidden = NSStatusBar.system.statusItem(withLength: btnAlwaysHiddenLength)
            if let button = btnAlwaysHidden?.button {
                button.image = self.imgIconLine
                button.appearsDisabled = true
            }
            self.btnAlwaysHidden?.autosaveName = "hiddenbar_terminate" + StatusBarController.autosaveSuffix
            self.btnAlwaysHidden?.isVisible = true
        } else {
            if let existing = self.btnAlwaysHidden {
                NSStatusBar.system.removeStatusItem(existing)
            }
            self.btnAlwaysHidden = nil
        }
    }
}
