//
//  StatusBarController.swift
//  vanillaClone
//
//  Created by Thanh Nguyen on 1/30/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import AppKit

// macOS persists where each status item sits as
// "NSStatusItem Preferred Position <autosaveName>" in the app's own defaults, and
// reads it when the item is created. A LARGER value places the item FURTHER LEFT
// (verified on macOS 26.5). The app only works when the order is, left to right:
// always-hidden, separator, arrow — the arrow has to stay to the right of the
// separator or the collapse swallows it and the bar can no longer be reopened.
//
// Those values outlive an uninstall and can be left stale by an older build or by
// a Cmd-drag, so validate them before the items exist. Nothing is rewritten while
// the order is sound. A broken order is repaired around the separator, which keeps
// its slot: that slot is what defines the hidden zone, so moving it would silently
// un-hide everything the user had parked there.
enum StatusItemPositions {
    private static let arrowKey = "NSStatusItem Preferred Position hiddenbar_expandcollapse"
    private static let separatorKey = "NSStatusItem Preferred Position hiddenbar_separate"
    private static let alwaysHiddenKey = "NSStatusItem Preferred Position hiddenbar_terminate"

    static func repairIfNeeded() {
        let defaults = UserDefaults.standard
        let arrow = defaults.object(forKey: arrowKey) as? Double
        let separator = defaults.object(forKey: separatorKey) as? Double
        let alwaysHidden = defaults.object(forKey: alwaysHiddenKey) as? Double

        // Fresh install: nothing saved, creation order already gives the right layout.
        if arrow == nil && separator == nil && alwaysHidden == nil { return }
        if isOrderValid(arrow: arrow, separator: separator, alwaysHidden: alwaysHidden) { return }

        func describe(_ value: Double?) -> String {
            guard let value = value else { return "nil" }
            return String(value)
        }
        // The separator is the anchor, never the thing that moves: its saved slot is
        // what defines the hidden zone, and every icon the user parked outside it stays
        // hidden only as long as the separator keeps that slot. Swapping slots around,
        // or clearing them, drags the zone with it and hiding silently becomes a no-op.
        // So leave the separator alone and pull the misplaced items to their own side.
        guard let separator = separator else {
            // No anchor. The separator will be placed by creation order, outside every
            // item that owns a slot, so a slot on the always-hidden item puts it on the
            // wrong side. Drop it and let creation order place that one too.
            NSLog("StatusItemPositions: stale order (arrow=\(describe(arrow)) alwaysHidden=\(describe(alwaysHidden))) with no separator slot; clearing the always-hidden slot")
            defaults.removeObject(forKey: alwaysHiddenKey)
            return
        }

        let repairedArrow = isOuter(separator, than: arrow) ? arrow : inward(of: separator)
        let repairedAlwaysHidden = alwaysHidden.map { isOuter($0, than: separator) ? $0 : outward(of: separator) }

        NSLog("StatusItemPositions: stale order (arrow=\(describe(arrow)) separator=\(describe(separator)) alwaysHidden=\(describe(alwaysHidden))); repaired to (arrow=\(describe(repairedArrow)) separator=\(describe(separator)) alwaysHidden=\(describe(repairedAlwaysHidden)))")

        if let repairedArrow = repairedArrow {
            defaults.set(repairedArrow, forKey: arrowKey)
        }
        if let repairedAlwaysHidden = repairedAlwaysHidden {
            defaults.set(repairedAlwaysHidden, forKey: alwaysHiddenKey)
        }
    }

    // One icon slot is worth roughly 40 preferred-position units on macOS 26; a gap of
    // 50 moves the item clear of its neighbour without hopping over a second one.
    private static let slotGap: Double = 50

    private static func inward(of position: Double) -> Double {
        let isLTR = NSApplication.shared.userInterfaceLayoutDirection == .leftToRight
        return isLTR ? position - slotGap : position + slotGap
    }

    private static func outward(of position: Double) -> Double {
        let isLTR = NSApplication.shared.userInterfaceLayoutDirection == .leftToRight
        return isLTR ? position + slotGap : position - slotGap
    }

    // Rescue path: the arrow was collapsed off-screen, so force it to the inner side of
    // the separator. Falls back to clearing every slot when there is no separator slot
    // to anchor to — that costs the hidden zone, but the arrow has to come back.
    static func pullArrowInside() {
        let defaults = UserDefaults.standard
        guard let separator = defaults.object(forKey: separatorKey) as? Double else {
            NSLog("StatusItemPositions: no separator slot to anchor the arrow to; clearing all slots")
            reset()
            return
        }
        let arrow = inward(of: separator)
        NSLog("StatusItemPositions: pulling the arrow inside the separator (arrow=\(arrow) separator=\(separator))")
        defaults.set(arrow, forKey: arrowKey)
    }

    static func reset() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: arrowKey)
        defaults.removeObject(forKey: separatorKey)
        defaults.removeObject(forKey: alwaysHiddenKey)
    }

    private static func isOrderValid(arrow: Double?, separator: Double?, alwaysHidden: Double?) -> Bool {
        // macOS only persists a position once an item has been placed or dragged, so a
        // partially saved set is normal, not corruption. An item with no saved value is
        // placed by creation order, at the outer end of the app's own group — exactly
        // where the always-hidden item and the separator belong. Treat "missing" as
        // "outermost" and require the group to read, outer to inner:
        // always-hidden, separator, arrow.
        return isOuter(alwaysHidden, than: separator) && isOuter(separator, than: arrow)
    }

    // True when `outer` sits further from the arrow than `inner`. A missing outer value
    // is always fine (it lands outermost); a missing inner value under a saved outer one
    // is not, because the inner item would be placed past the outer one.
    private static func isOuter(_ outer: Double?, than inner: Double?) -> Bool {
        guard let outer = outer else { return true }
        guard let inner = inner else { return false }

        // Constant.isUsingLTRLanguage is only assigned in applicationDidFinishLaunching,
        // which runs after the status items are built. Read the direction directly.
        // A larger preferred position means further left, so LTR wants outer > inner.
        let isLTR = NSApplication.shared.userInterfaceLayoutDirection == .leftToRight
        return isLTR ? outer > inner : outer < inner
    }
}

class StatusBarController {
    
    //MARK: - Variables
    private var timer:Timer? = nil
    
    //MARK: - BarItems
        
    private var btnExpandCollapse: NSStatusItem
    private var btnSeparate: NSStatusItem
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
    
    // macOS 26 positions status-item windows asynchronously: for roughly the first
    // second after launch every button window still reports origin (0,0). The order
    // checks below compare those origins, and comparing zeros made them trivially
    // true, so the app collapsed before it could tell the arrow from the separator.
    // With a stale saved order that swallowed its own expand/collapse arrow and left
    // the user with no way to bring the bar back (#336-family "no arrow" reports).
    // Unplaced geometry is "unknown", never "valid".
    private var isMenuBarGeometryReady: Bool {
        guard
            let btnExpandCollapseOrigin = self.btnExpandCollapse.button?.getOrigin,
            let btnSeparateOrigin = self.btnSeparate.button?.getOrigin
            else {return false}

        return btnExpandCollapseOrigin != .zero && btnSeparateOrigin != .zero
    }

    private var isBtnSeparateValidPosition: Bool {
        guard self.isMenuBarGeometryReady else {return false}

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

        guard self.isMenuBarGeometryReady else {return false}

        guard
            let btnSeparateX = self.btnSeparate.button?.getOrigin?.x,
            let btnAlwaysHiddenOrigin = self.btnAlwaysHidden?.button?.getOrigin,
            btnAlwaysHiddenOrigin != .zero
            else {return false}

        let btnAlwaysHiddenX = btnAlwaysHiddenOrigin.x
        if Constant.isUsingLTRLanguage {
            return btnSeparateX >= btnAlwaysHiddenX
        } else {
            return btnSeparateX <= btnAlwaysHiddenX
        }
    }
    
    private var isToggle = false

    // SPEC-003 (macOS 27 hide-mechanism). macOS 27 re-architected the menu bar so
    // inflating the separator length may no longer push items off-screen (#360).
    // This is DIAGNOSTIC ONLY: on the first collapse with the menu-bar window
    // ready, log the separator geometry so a macOS 27 run reveals which signal
    // (if any) distinguishes "length honored" from "ignored". No behavior change.
    // The degrade ACTION is deliberately NOT shipped: review found the trigger
    // unverifiable without 27 hardware, and a false positive would disable hiding
    // for a working user. The action lands once this log calibrates the signal.
    private var hideMechanismChecked = false

    private var arrowRescueCount = 0

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
        // Must run before the first statusItem() call: macOS reads the saved
        // "NSStatusItem Preferred Position" when the item is created, so a stale
        // order can only be corrected up front.
        StatusItemPositions.repairIfNeeded()
        btnExpandCollapse = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        btnSeparate = NSStatusBar.system.statusItem(withLength: 1)

        updateCollapsedLengths()
        setupUI()
        restoreRemovedStatusItems()
        setupAlwayHideStatusBar()
        setupHoverToExpandIfEnabled()
        NotificationCenter.default.addObserver(self, selector: #selector(handleScreenParametersChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateAutoHide), name: .prefsChanged, object: nil)
        collapseWhenGeometryReady()

        if Preferences.areSeparatorsHidden {hideSeparators()}
        autoCollapseIfNeeded()
    }

    // The launch collapse used to fire on a flat 1s delay. On macOS 26 the status-item
    // windows are not always placed by then, and collapsing before the order can be
    // verified is exactly what hides the arrow. Wait for real geometry instead.
    private func collapseWhenGeometryReady(attempt: Int = 0) {
        let maxAttempts = 20
        let delay = attempt == 0 ? 1.0 : 0.25
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            if self.isMenuBarGeometryReady || attempt >= maxAttempts {
                self.collapseMenuBar()
            } else {
                self.collapseWhenGeometryReady(attempt: attempt + 1)
            }
        }
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
        rescueArrowIfSwallowed()
    }

    // Last line of defence. If a collapse ever leaves the expand/collapse arrow off
    // every screen, the app has hidden its own only control and the bar cannot be
    // brought back by clicking. Undo the collapse, fix the stored order, and rebuild
    // the items so the arrow comes back in this session rather than after a restart.
    private func rescueArrowIfSwallowed() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isCollapsed else { return }
            guard let arrowFrame = self.btnExpandCollapse.button?.window?.frame,
                  arrowFrame.origin != .zero else { return }
            guard !NSScreen.screens.contains(where: { $0.frame.intersects(arrowFrame) }) else { return }

            // Bounded: a reset that does not take must not turn into a collapse/rescue
            // ping-pong. After the budget is spent the arrow simply stays put.
            guard self.arrowRescueCount < 2 else {
                NSLog("ArrowRescue: giving up after \(self.arrowRescueCount) attempts; leaving the bar expanded")
                self.expandMenubar()
                return
            }
            self.arrowRescueCount += 1

            NSLog("ArrowRescue: arrow ended up off-screen at \(arrowFrame); expanding and rebuilding status items")
            self.expandMenubar()
            StatusItemPositions.pullArrowInside()
            self.rebuildStatusItems()
        }
    }

    private func rebuildStatusItems() {
        NSStatusBar.system.removeStatusItem(btnExpandCollapse)
        NSStatusBar.system.removeStatusItem(btnSeparate)
        btnExpandCollapse = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        btnSeparate = NSStatusBar.system.statusItem(withLength: 1)
        setupUI()
        restoreRemovedStatusItems()
        btnSeparate.length = btnHiddenLength
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

    // After a collapse, confirm on the next runloop tick (so layout settles) that
    // the separator actually claimed its inflated width. macOS <= 26 honors it;
    // a macOS that ignores NSStatusItem.length leaves the slot narrow, meaning
    // hiding did nothing. Checked once: cheap, and the OS behavior won't change
    // mid-session.
    private func verifyHideMechanismIfNeeded() {
        guard !hideMechanismChecked else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isCollapsed else { return }
            // Need the separator's backing window to measure. If it is not up yet
            // (early launch), do NOT burn the one-shot check: return and let a
            // later collapse retry once the window exists.
            guard let separatorButton = self.btnSeparate.button,
                  let window = separatorButton.window else { return }
            self.hideMechanismChecked = true
            // Log several geometry signals. On macOS <= 26 the inflation is
            // honored; on macOS 27 it may be ignored. Which of these tracks the
            // requested length is exactly what a 27 capture must reveal before any
            // degrade action can trigger on a sound signal.
            let requested = self.btnHiddenCollapseLength
            let windowWidth = window.frame.width
            let buttonWidth = separatorButton.frame.width
            // The arrow's own frame is logged alongside: a collapse that pushes the
            // arrow off every screen is the failure that leaves the bar unreopenable.
            let arrowFrame = self.btnExpandCollapse.button?.window?.frame ?? .zero
            let arrowOnScreen = NSScreen.screens.contains { $0.frame.intersects(arrowFrame) }
            NSLog("HideMechanism: requested=\(requested) windowWidth=\(windowWidth) buttonWidth=\(buttonWidth) length=\(self.btnSeparate.length) arrowFrame=\(arrowFrame) arrowOnScreen=\(arrowOnScreen)")
        }
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
