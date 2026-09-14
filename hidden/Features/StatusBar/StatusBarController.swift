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

    // SPEC-003 (macOS 27 hide mechanism, #360). Measured on 27.0 (build 26A428),
    // 1800pt notched display.
    //
    // Hiding works by inflating the separator until everything to its left leaves
    // the visible bar. macOS <= 26 reflowed around any length, so asking for 2x the
    // screen width always worked and the size never had to be thought about.
    //
    // macOS 27 changed that: an over-long status item is EJECTED from the menu-bar
    // layout rather than laid out, and an ejected item pushes nothing. Captured
    // with a victim icon in the hidden section:
    //
    //     300pt  -> honored, whole hidden section collapses into the OS overflow
    //     600pt  -> honored, same
    //     1000pt -> ejected, nothing hidden
    //     3600pt -> ejected, nothing hidden   <- what this app used to request
    //
    // The cutoff is where the separator would grow past the left edge of the status
    // region (the notch on this display, the app menus elsewhere), so it depends on
    // the display AND on how full the bar currently is. It cannot be a constant.
    //
    // Ejection is observable without private API. The separator sits immediately
    // beside the arrow, so while it is laid out it can only grow AWAY from the
    // arrow, which pins the edge nearest the arrow in place: the item gets wider
    // but that edge does not move. An ejected item instead keeps its narrow
    // position and reports a frame that runs straight past the arrow, so the same
    // edge jumps by roughly the requested length. Measured, LTR, baseline right
    // edge 1225pt:
    //
    //     160pt  -> right edge 1217  (moved 8pt)    laid out, hides
    //     300pt  -> right edge 1217  (moved 8pt)    laid out, hides
    //     600pt  -> right edge 1217  (moved 8pt)    laid out, hides
    //     1000pt -> right edge 2224  (moved 999pt)  ejected, hides nothing
    //
    // The 8pt is the status window's own padding, hence the tolerance below. Note
    // the ORIGIN is not a usable signal: it also moves for ejected items, which
    // makes them look laid out.
    //
    // nil means "not calibrated yet"; it is recalculated on display changes.
    private var honoredCollapseLength: CGFloat?
    private var isCalibratingCollapseLength = false

    // macOS <= 26 lays out any length, and the pinned-edge signal above is
    // unverified on those versions, so leave their behavior exactly as it was.
    private var needsCollapseLengthCalibration: Bool {
        return ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
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
            self?.collapseMenuBar()
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
        // The honored cutoff depends on the display's status region, so a hot-plug
        // invalidates it and the next collapse has to measure again.
        honoredCollapseLength = nil
        if wasCollapsed {
            recollapseAndRecalibrate()
        }
    }

    // Calibration needs the separator's resting origin as its reference, and that
    // only exists while expanded. So drop to the expanded width for one hop, then
    // collapse again through the normal path, which re-measures.
    private func recollapseAndRecalibrate() {
        btnSeparate.length = btnHiddenLength
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            self.collapseMenuBar()
            self.applyAlwaysHiddenCollapseLengthIfCollapsed()
        }
    }

    // The always-hidden section inflates its own item the same way, so it hits the
    // same macOS 27 ejection cutoff. The separator's calibrated value stands in for
    // it: measured on the same bar, and vastly closer than the old 2x-screen-width
    // request. A separate search would need its own resting origin for one extra
    // item, which is not worth a second calibration pass.
    private func alwaysHiddenCollapseLength() -> CGFloat {
        guard needsCollapseLengthCalibration,
              let calibrated = honoredCollapseLength else {
            return btnAlwaysHiddenEnableExpandCollapseLength
        }
        return min(btnAlwaysHiddenEnableExpandCollapseLength, calibrated)
    }

    private func applyAlwaysHiddenCollapseLengthIfCollapsed() {
        guard Preferences.areSeparatorsHidden else { return }
        btnAlwaysHidden?.length = alwaysHiddenCollapseLength()
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
        self.btnAlwaysHidden?.length = self.alwaysHiddenCollapseLength()
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
        guard self.isBtnSeparateValidPosition && !self.isCollapsed else {
            autoCollapseIfNeeded()
            return
        }

        // Where the separator's arrow-facing edge sits while expanded. Calibration
        // compares against this to tell "still in the layout" from "ejected", so it
        // has to be read before the length changes.
        let restingEdge = separatorEdgeFacingArrow()

        btnSeparate.length = self.collapseLengthToApply()
        if let button = btnExpandCollapse.button {
            button.image = Assets.expandImage
        }
        if Preferences.useFullStatusBarOnExpandEnabled {
            NSApp.setActivationPolicy(.accessory)
            NSApp.deactivate()
        }
        calibrateCollapseLengthIfNeeded(restingEdge: restingEdge)
    }

    // On macOS 27 the calibrated length replaces the requested one; before it has
    // been measured, the full request is used so the very first collapse is no
    // worse than the old behavior.
    private func collapseLengthToApply() -> CGFloat {
        guard needsCollapseLengthCalibration else { return btnHiddenCollapseLength }
        return honoredCollapseLength ?? btnHiddenCollapseLength
    }
    private func expandMenubar() {
        guard self.isCollapsed else {return}
        btnSeparate.length = btnHiddenLength
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

    // Find the largest collapse length macOS will still lay out, then keep using
    // it. Runs at most once per display configuration: the search costs a few
    // runloop hops and the answer only moves when the bar's geometry does.
    private func calibrateCollapseLengthIfNeeded(restingEdge: CGFloat?) {
        guard needsCollapseLengthCalibration,
              honoredCollapseLength == nil,
              !isCalibratingCollapseLength else { return }
        // No backing window yet (very early launch) means nothing is measurable.
        // Return WITHOUT latching so a later collapse retries; latching here would
        // burn the calibration on a transient nil and leave hiding broken.
        guard let restingEdge = restingEdge,
              btnSeparate.button?.window != nil else { return }

        isCalibratingCollapseLength = true
        binarySearchHonoredLength(restingEdge: restingEdge,
                                  upperBound: btnHiddenCollapseLength)
    }

    // The edge of the separator that faces the arrow. A laid-out separator grows
    // away from the arrow and leaves this edge where it was; an ejected one lets it
    // run past the arrow. In LTR the arrow is to the right of the separator, in RTL
    // to the left, so the edge to watch flips with the layout direction.
    private func separatorEdgeFacingArrow() -> CGFloat? {
        guard let frame = btnSeparate.button?.window?.frame else { return nil }
        return Constant.isUsingLTRLanguage ? frame.maxX : frame.minX
    }

    // 8pt of status-window padding is normal; anything beyond half an icon width
    // means the frame ran past the arrow, i.e. the item left the layout.
    private func isSeparatorLaidOut(restingEdge: CGFloat) -> Bool {
        guard let edge = separatorEdgeFacingArrow() else { return false }
        return abs(edge - restingEdge) <= 24
    }

    private func binarySearchHonoredLength(restingEdge: CGFloat, upperBound: CGFloat) {
        // btnHiddenLength is the expanded width, trivially laid out, so it is a safe
        // lower bound. Everything probed stays above it, which keeps isCollapsed
        // true throughout and stops the auto-collapse timer fighting the search.
        var lo = btnHiddenLength
        var hi = upperBound
        var best = lo
        var iterations = 0

        func probeNext() {
            // 9 hops resolve a 3600pt range to ~8pt, which is far finer than an icon.
            guard iterations < 9, hi - lo > 8 else { return finish() }
            iterations += 1
            let mid = ((lo + hi) / 2).rounded()
            btnSeparate.length = mid
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self = self else { return }
                let laidOut = self.isSeparatorLaidOut(restingEdge: restingEdge)
                NSLog("HideMechanism: probe \(mid)pt edge=\(self.separatorEdgeFacingArrow() ?? -1) resting=\(restingEdge) -> \(laidOut ? "laid out" : "ejected")")
                if laidOut {
                    best = mid
                    lo = mid
                } else {
                    hi = mid
                }
                probeNext()
            }
        }

        func finish() {
            // If nothing above the expanded width survived, this OS will not lay out
            // an inflated separator at all and hiding is genuinely unavailable. Stay
            // strictly above btnHiddenLength anyway so isCollapsed keeps reporting
            // the real state instead of silently reading as "expanded".
            let calibrated = max(best, btnHiddenLength + 1)
            honoredCollapseLength = calibrated
            isCalibratingCollapseLength = false
            NSLog("HideMechanism: calibrated collapse length \(calibrated)pt (requested \(upperBound)pt)")
            if best <= btnHiddenLength {
                NSLog("HideMechanism: no inflated length is laid out on this display, hiding unavailable")
            }
            if isCollapsed {
                btnSeparate.length = calibrated
                applyAlwaysHiddenCollapseLengthIfCollapsed()
            }
        }

        probeNext()
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
