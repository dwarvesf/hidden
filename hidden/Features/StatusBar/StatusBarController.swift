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

    // macOS 27 hide-mechanism (#360). On macOS 27 ("Golden Gate") inflating the
    // separator grows OUR item's own backing window wider than the screen without
    // pushing neighboring icons off-screen: hiding silently does nothing. We detect
    // that on the first collapse and degrade gracefully (stop inflating, restore the
    // bar, notify once). The whole action is gated behind macOS >= 27, so macOS <= 26
    // behavior is byte-identical.
    private var hideMechanismChecked = false
    // Latched once the degrade has run, to stop any further collapse/auto-hide
    // attempt from re-inflating the separator in a loop.
    private var hideDegraded = false
    // Context-menu item revealed only while degraded; links to #360.
    private weak var macOS27NoticeMenuItem: NSMenuItem?

    private static let macOS27IssueURL = "https://github.com/dwarvesf/hidden/issues/360"

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
        // Once degraded on macOS 27 there is nothing to re-apply; never re-inflate.
        guard !hideDegraded else { return }
        // Re-apply the recomputed length to the LIVE item when collapsed, or a
        // display hot-plug leaves the separator at a stale length (PR #354).
        let wasCollapsed = isCollapsed
        updateCollapsedLengths()
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
        // After the macOS 27 degrade there is nothing to hide; don't re-inflate
        // the always-hidden separator into a dead zone.
        guard !hideDegraded else { return }
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
    
    private func collapseMenuBar() {
        // macOS 27 (#360): hiding has been confirmed unavailable, so do not inflate.
        guard !hideDegraded else { return }
        // If a previous launch already confirmed hiding is unavailable on macOS 27
        // (the one-time notice was shown), degrade up front instead of inflating the
        // separator first — otherwise it visibly stretches then snaps back on every
        // launch. The notice flag is only ever set on macOS 27.
        if ProcessInfo.processInfo.isMacOS27OrLater, Preferences.didShowMacOS27HideUnavailableNotice {
            degradeHideUnavailable()
            return
        }
        guard self.isBtnSeparateValidPosition && !self.isCollapsed else {
            autoCollapseIfNeeded()
            return
        }

        btnSeparate.length = self.btnHiddenCollapseLength
        if let button = btnExpandCollapse.button {
            button.image = Assets.expandImage
        }
        if Preferences.useFullStatusBarOnExpandEnabled {
            NSApp.setActivationPolicy(.accessory)
            NSApp.deactivate()
        }
        verifyHideMechanismIfNeeded()
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
        guard !hideDegraded else { return }
        guard Preferences.isAutoHide else {return}
        guard !isCollapsed else { return }

        startTimerToAutoHide()
    }

    // After a collapse, confirm on the next runloop tick (so layout settles)
    // whether inflating the separator actually hid neighbors. macOS <= 26 shares one
    // menu-bar window across all items, so the separator's backing window stays
    // screen-wide (honored). macOS 27 gives each item its own window, so inflating
    // grows that window wider than the screen while neighbors stay put (ignored):
    // hiding is a no-op. Checked once; the OS behavior won't change mid-session.
    private func verifyHideMechanismIfNeeded() {
        guard !hideMechanismChecked else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isCollapsed else { return }
            guard !self.hideMechanismChecked else { return }
            // Need the separator's backing window to measure. If it is not up yet
            // (early launch), do NOT burn the one-shot check: return and let a
            // later collapse retry once the window exists.
            guard let separatorButton = self.btnSeparate.button,
                  let window = separatorButton.window else { return }
            // Latch only AFTER a real measurement is possible, so a transient nil
            // window never burns the one-shot check.
            self.hideMechanismChecked = true

            let requested = self.btnHiddenCollapseLength
            let windowWidth = window.frame.width
            let buttonWidth = separatorButton.frame.width
            let screenWidth = NSScreen.screens.map { $0.frame.width }.max() ?? 0
            NSLog("HideMechanism: requested=\(requested) windowWidth=\(windowWidth) buttonWidth=\(buttonWidth) length=\(self.btnSeparate.length) screenWidth=\(screenWidth) os=\(ProcessInfo.processInfo.operatingSystemVersionString)")

            // The degrade action is macOS-27-only: macOS <= 26 keeps the diagnostic
            // log above and nothing else, so its behavior is byte-identical.
            guard ProcessInfo.processInfo.isMacOS27OrLater else { return }

            // No `?? requested` fallback: an unmeasurable outcome is never coerced
            // to "honored". `ignored` and `inconclusive` both degrade (on macOS 27
            // hiding is broken regardless, so a residual false positive is safe).
            switch self.evaluateHideOutcome(separatorWindow: window, screenWidth: screenWidth) {
            case .honored:
                break // a macOS 27.x that restored the trick: keep hiding, do nothing
            case .ignored, .inconclusive:
                self.degradeHideUnavailable()
            }
        }
    }

    private enum HideOutcome {
        case honored      // inflation displaced neighbors -> hiding works
        case ignored      // inflation only grew our own window -> hiding is a no-op (#360)
        case inconclusive // could not measure
    }

    // Discriminate "hiding worked" from "hiding is a no-op" by whether the
    // separator's backing window is wider than the screen. macOS <= 26 packs every
    // status item into ONE shared menu-bar window whose width is the screen width,
    // no matter how long our item is. macOS 27 gives each item its OWN window, so
    // inflating grows that window far wider than the screen. A separator window
    // wider than its screen therefore means the inflation stayed inside our own item
    // and displaced nothing. (The system caps the inflated window near ~5000pt, so
    // comparing against the requested length is unreliable; the screen width is the
    // stable reference.) Only consulted under the macOS-27 gate.
    private func evaluateHideOutcome(separatorWindow: NSWindow, screenWidth: CGFloat) -> HideOutcome {
        guard screenWidth > 0 else { return .inconclusive }
        let ownWindowExceedsScreen = separatorWindow.frame.width > screenWidth * 1.1
        return ownWindowExceedsScreen ? .ignored : .honored
    }

    // macOS 27 (#360): stop the futile inflation, return the bar to its expanded
    // state, and tell the user once. Idempotent.
    private func degradeHideUnavailable() {
        guard !hideDegraded else { return }
        hideDegraded = true

        // Undo the inflation so the bar looks normal instead of leaving a wide
        // empty slot. isCollapsed derives from btnSeparate.length, so resetting it
        // to btnHiddenLength makes isCollapsed == false: state stays consistent.
        btnSeparate.length = btnHiddenLength
        if Preferences.areSeparatorsHidden {
            btnAlwaysHidden?.length = btnAlwaysHiddenLength
        }
        if let button = btnExpandCollapse.button {
            button.image = Assets.collapseImage
        }

        // collapseMenuBar() switched the app to .accessory and deactivated it under
        // "use full menu bar on expanding". Mirror expandMenubar()'s restore, or the
        // bar shows while the app stays stuck in .accessory.
        if Preferences.useFullStatusBarOnExpandEnabled {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }

        // Kill the auto-hide and hover timers so neither can re-enter collapse logic.
        timer?.invalidate()
        timer = nil
        hoverDwellTimer?.invalidate()
        hoverDwellTimer = nil

        macOS27NoticeMenuItem?.isHidden = false
        NSLog("HideMechanism: degraded - macOS 27 hide unavailable (#360)")

        if !Preferences.didShowMacOS27HideUnavailableNotice {
            Preferences.didShowMacOS27HideUnavailableNotice = true
            presentMacOS27DegradeAlert()
        }
    }

    private func presentMacOS27DegradeAlert() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Menu bar hiding isn't available on macOS 27".localized
        alert.informativeText = "macOS 27 changed how the menu bar works, so Hidden Bar can no longer hide other apps' icons by collapsing. This is a known limitation tracked on GitHub; Hidden Bar will stay out of the way until a compatible method is available.".localized
        alert.addButton(withTitle: "Learn More".localized)
        alert.addButton(withTitle: "OK".localized)
        // Accessory apps don't own the active state; pull the alert to the front.
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            openMacOS27Notice()
        }
    }

    @objc private func openMacOS27Notice() {
        guard let url = URL(string: StatusBarController.macOS27IssueURL) else { return }
        NSWorkspace.shared.open(url)
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
        
        // Hidden until the macOS 27 degrade runs; then it links to #360 so users
        // understand why hiding stopped. A hidden item renders nothing, so the menu
        // is unchanged on macOS <= 26 and before degrade.
        let noticeItem = NSMenuItem(title: "Hiding unavailable on macOS 27 - Learn more".localized, action: #selector(openMacOS27Notice), keyEquivalent: "")
        noticeItem.target = self
        noticeItem.isHidden = true
        menu.addItem(noticeItem)
        self.macOS27NoticeMenuItem = noticeItem

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
