//
//  StatusBarController.swift
//  vanillaClone
//
//  Created by Thanh Nguyen on 1/30/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import AppKit

class StatusBarController {
    
    //MARK: - Variables
    private var timer:Timer? = nil
    
    //MARK: - BarItems
        
    private let btnExpandCollapse = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let btnSeparate = NSStatusBar.system.statusItem(withLength: 1)
    private var btnAlwaysHidden:NSStatusItem? = nil
    
    private var btnHiddenLength: CGFloat = 20
    private var btnHiddenCollapseLength: CGFloat = 2000
    
    private var btnAlwaysHiddenLength: CGFloat = Preferences.alwaysHiddenSectionEnabled ? 20 : 0
    private var btnAlwaysHiddenEnableExpandCollapseLength: CGFloat = Preferences.alwaysHiddenSectionEnabled ? 2000 : 0
    
    private let imgIconLine = NSImage(named:NSImage.Name("ic_line"))
    
    private var isCollapsed: Bool {
        // Compare with > rather than == so the state survives updateCollapsedLengths
        // changing btnHiddenCollapseLength while the bar is collapsed (PR #354).
        return self.btnSeparate.length > self.btnHiddenLength
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

    // SPEC-003 (macOS 27 hide-mechanism). macOS 27 re-architected the menu bar so
    // inflating the separator length no longer pushes other status items
    // off-screen (#360). The separator still grows, but its X position and
    // neighboring items no longer move with it.
    private struct HideMechanismGeometry {
        let separatorMinX: CGFloat
        let separatorWidth: CGFloat
        let arrowMinX: CGFloat
    }

    private var hideMechanismChecked = false
    private var isHideMechanismUnavailable = false
    private let hideMechanismNoticeTag = 27360

    private var hoverMonitor: Any?
    private var hoverDwellTimer: Timer?

    private var needsHideMechanismVerification: Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
            && ProcessInfo.processInfo.environment["HIDDENBAR_DIAG"] == nil
    }

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
            self?.collapseMenuBar()
        }

        if Preferences.areSeparatorsHidden {hideSeparators()}
        autoCollapseIfNeeded()

        if ProcessInfo.processInfo.environment["HIDDENBAR_DIAG"] != nil {
            runHideMechanismDiagnostic()
        }
    }

    // SPEC-003 / #360 capture. Self-triggering geometry probe, gated behind the
    // HIDDENBAR_DIAG env var so it never runs for normal users. Waits for the
    // status-item windows to exist, logs the EXPANDED geometry, forces a collapse,
    // then logs the COLLAPSED geometry. On macOS 27, the width grows while the
    // X positions stay fixed, so the old layout-displacement trick is unavailable.
    private func runHideMechanismDiagnostic() {
        func geom(_ label: String) {
            let sepW = btnSeparate.button?.window?.frame.width ?? -1
            let sepX = btnSeparate.button?.window?.frame.minX ?? -1
            let arrW = btnExpandCollapse.button?.window?.frame.width ?? -1
            let arrX = btnExpandCollapse.button?.window?.frame.minX ?? -1
            NSLog("DIAG[\(label)]: separate.length=\(btnSeparate.length) requestedCollapse=\(btnHiddenCollapseLength) sepWinW=\(sepW) sepWinX=\(sepX) arrWinW=\(arrW) arrWinX=\(arrX) isCollapsed=\(isCollapsed)")
        }
        // Retry until the backing windows are up (they are nil right after launch).
        func attempt(_ tries: Int) {
            guard tries > 0 else { NSLog("DIAG: gave up waiting for status-item window"); return }
            guard btnSeparate.button?.window != nil, btnExpandCollapse.button?.window != nil else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { attempt(tries - 1) }
                return
            }
            let screens = NSScreen.screens.map { "\($0.frame.width)x\($0.frame.height)" }.joined(separator: ",")
            NSLog("DIAG: macOS=\(ProcessInfo.processInfo.operatingSystemVersionString) screens=[\(screens)]")
            // Ensure expanded baseline, measure, collapse, measure.
            if isCollapsed { expandMenubar() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                geom("expanded")
                self.btnSeparate.length = self.btnHiddenCollapseLength
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    geom("collapsed")
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { attempt(10) }
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
        if isHideMechanismUnavailable {
            restoreExpandedMenuBarState()
            return
        }
        if wasCollapsed {
            btnSeparate.length = btnHiddenCollapseLength
            if Preferences.areSeparatorsHidden {
                btnAlwaysHidden?.length = btnAlwaysHiddenEnableExpandCollapseLength
            }
        }
    }

    private func updateCollapsedLengths() {
        // The menubar replicates across every attached display, so the collapse
        // length must cover the WIDEST screen, not NSScreen.main (the focused one);
        // sizing from a narrower screen leaks hidden icons on wider displays.
        // frame.width, not visibleFrame: the menubar spans the full frame width.
        let screenWidth = NSScreen.screens.map { $0.frame.width }.max() ?? 1728
        // Keep collapse length bounded to avoid pathological layout/memory behavior;
        // macOS enforces a hard 10,000pt maximum on NSStatusItem.length (PR #354).
        let boundedCollapseLength = max(500, min(screenWidth * 2, 10_000))
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
        
        btnExpandCollapse.autosaveName = "hiddenbar_expandcollapse";
        btnSeparate.autosaveName = "hiddenbar_separate";
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
        guard !isHideMechanismUnavailable else {
            self.btnAlwaysHidden?.length = self.btnAlwaysHiddenLength
            return
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
    
    private func collapseMenuBar() {
        guard !isHideMechanismUnavailable else {
            addHideMechanismUnavailableNotice()
            return
        }
        guard self.isBtnSeparateValidPosition && !self.isCollapsed else {
            autoCollapseIfNeeded()
            return
        }

        let before = hideMechanismGeometry()
        btnSeparate.length = self.btnHiddenCollapseLength
        if let button = btnExpandCollapse.button {
            button.image = Assets.expandImage
        }
        if Preferences.useFullStatusBarOnExpandEnabled {
            NSApp.setActivationPolicy(.accessory)
            NSApp.deactivate()
        }
        verifyHideMechanismIfNeeded(before: before)
    }
    private func expandMenubar() {
        guard self.isCollapsed else {return}
        restoreExpandedMenuBarState()
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

    private func restoreExpandedMenuBarState() {
        btnSeparate.length = btnHiddenLength
        btnAlwaysHidden?.length = btnAlwaysHiddenLength
        if let button = btnExpandCollapse.button {
            button.image = Assets.collapseImage
        }
    }

    private func hideMechanismGeometry() -> HideMechanismGeometry? {
        guard
            let separatorWindow = btnSeparate.button?.window,
            let arrowWindow = btnExpandCollapse.button?.window
        else { return nil }

        return HideMechanismGeometry(
            separatorMinX: separatorWindow.frame.minX,
            separatorWidth: separatorWindow.frame.width,
            arrowMinX: arrowWindow.frame.minX
        )
    }

    // After a collapse, confirm that the inflated separator still participates
    // in menu-bar layout. On macOS 27 it grows in place, so neighboring items do
    // not move and hiding is unavailable.
    private func verifyHideMechanismIfNeeded(before: HideMechanismGeometry?) {
        guard needsHideMechanismVerification, !hideMechanismChecked else { return }
        guard let before = before else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self = self, self.isCollapsed else { return }
            guard let after = self.hideMechanismGeometry() else { return }

            self.hideMechanismChecked = true
            let requested = self.btnHiddenCollapseLength
            let separatorShift = abs(after.separatorMinX - before.separatorMinX)
            let arrowShift = abs(after.arrowMinX - before.arrowMinX)
            let requiredShift = min(100, requested * 0.1)
            let didDisplaceItems = max(separatorShift, arrowShift) >= requiredShift

            NSLog("HideMechanism: requested=\(requested) beforeSepX=\(before.separatorMinX) afterSepX=\(after.separatorMinX) beforeArrowX=\(before.arrowMinX) afterArrowX=\(after.arrowMinX) afterSepWidth=\(after.separatorWidth) displaced=\(didDisplaceItems)")

            if !didDisplaceItems {
                self.markHideMechanismUnavailable()
            }
        }
    }

    private func markHideMechanismUnavailable() {
        isHideMechanismUnavailable = true
        restoreExpandedMenuBarState()
        addHideMechanismUnavailableNotice()

        if Preferences.useFullStatusBarOnExpandEnabled {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }

        NSLog("HideMechanism: unavailable on this macOS version; restored expanded state")
    }

    private func addHideMechanismUnavailableNotice() {
        guard let menu = btnSeparate.menu,
              menu.item(withTag: hideMechanismNoticeTag) == nil
        else { return }

        let item = NSMenuItem(title: "Hiding is unavailable on this macOS version", action: nil, keyEquivalent: "")
        item.tag = hideMechanismNoticeTag
        item.isEnabled = false
        menu.insertItem(item, at: min(2, menu.numberOfItems))
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
            self.btnAlwaysHidden?.autosaveName = "hiddenbar_terminate"
            self.btnAlwaysHidden?.isVisible = true
        } else {
            if let existing = self.btnAlwaysHidden {
                NSStatusBar.system.removeStatusItem(existing)
            }
            self.btnAlwaysHidden = nil
        }
    }
}
