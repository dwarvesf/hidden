//
//  StatusBarController.swift
//  vanillaClone
//
//  Created by Thanh Nguyen on 1/30/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import AppKit

class StatusBarController: MenuBarItemProvider {
    
    //MARK: - Variables
    private var timer:Timer? = nil

    //MARK: - BarItems

    private let btnExpandCollapse = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let btnSeparate = NSStatusBar.system.statusItem(withLength: 1)
    private var btnAlwaysHidden:NSStatusItem? = nil

    //MARK: - Notch Overflow
    private var notchOverflowController = NotchOverflowController()
    
    var toggleItem: NSStatusItem { btnExpandCollapse }
    var separatorItem: NSStatusItem { btnSeparate }
    var alwaysHiddenItem: NSStatusItem? { btnAlwaysHidden }
    
    // How hiding is achieved (separator lengths) lives in the engine; this class
    // owns the items, the UI, and when to collapse or expand.
    private lazy var menuBarEngine: MenuBarEngine = MenuBarEngineFactory.make(items: self)

    // Read only when the auto-hide timer fires.
    private lazy var popupGuard = AutoCollapsePopupGuard(menuBarItemOwners: { [weak self] in
        self?.menuBarEngine.menuBarItemOwners ?? []
    })
    
    private let imgIconLine = NSImage(named:NSImage.Name("ic_line"))
    
    private var isCollapsed: Bool {
        return menuBarEngine.state == .collapsed
    }
    
    private var isBtnAlwaysHiddenValidPosition: Bool {
        if !Preferences.alwaysHiddenSectionEnabled { return true }
        return menuBarEngine.isAlwaysHiddenSeparatorPlaced
    }
    
    private var isToggle = false

    private var hoverMonitor: Any?
    private var pinnedSectionsObserver: NSObjectProtocol?
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
    // it is on screen, without creating the controller or loading its window
    // when preferences were never opened.
    private var isPreferencesWindowVisible: Bool {
        return PreferencesWindowController.isVisible
    }
    
    //MARK: - Methods
    init() {
        setupUI()
        restoreRemovedStatusItems()
        setupAlwayHideStatusBar()
        syncHoverToExpand()
        NotificationCenter.default.addObserver(self, selector: #selector(syncHoverToExpand), name: .prefsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleScreenParametersChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateAutoHide), name: .prefsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(syncActivationPolicyWithFullStatusBar), name: .useFullStatusBarToggle, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshArrow), name: .stealthExpandIconToggle, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshArrow), name: .arrowStyleChanged, object: nil)
        watchAccessibilityPermission()
        #if DEBUG
        installDebugHooks()
        #endif
        // Sections are read from where the items sit, so wait until macOS has put
        // them back in place (the always-hidden separator may have been taken
        // out of the bar when the app quit).
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.collapseAtLaunch(retriesLeft: 16)
        }

        autoCollapseIfNeeded()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        pinnedSectionsObserver.map(NotificationCenter.default.removeObserver)
        hoverDwellTimer?.invalidate()
        if let monitor = hoverMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // Opt-in via the Preferences checkbox (or `defaults write com.dwarvesv.minimalbar
    // hoverToExpand -bool true` before launch). No monitor exists unless the pref is
    // true; flipping it installs or removes the monitor at once.
    @objc private func syncHoverToExpand() {
        guard Preferences.hoverToExpand else {
            if let monitor = hoverMonitor { NSEvent.removeMonitor(monitor) }
            hoverMonitor = nil
            hoverDwellTimer?.invalidate()
            hoverDwellTimer = nil
            return
        }
        guard hoverMonitor == nil else { return }
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
                    self.menuBarEngine.userChangedBar()
                    self.expandMenubar()
                }
            }
        }
    }
    
    @objc private func handleScreenParametersChanged() {
        // Re-apply the recomputed length to the LIVE item when collapsed, or a
        // display hot-plug leaves the separator at a stale length (PR #354).
        let wasCollapsed = isCollapsed
        menuBarEngine.invalidateLayout()
        if wasCollapsed && Preferences.areSeparatorsHidden {
            menuBarEngine.updateAlwaysHiddenSection(enabled: Preferences.alwaysHiddenSectionEnabled, separatorHidden: true)
        }
    }
    
    private func restoreRemovedStatusItems() {
        // Cmd-dragging a status item off the bar is persisted by macOS via
        // autosaveName, leaving the app running but unreachable. These items are
        // the app's only UI, so they self-restore at launch.
        btnExpandCollapse.isVisible = true
        btnSeparate.isVisible = true
        // Create the engine now so one that does not use the separator (macOS 27
        // native hiding) takes it back out before it is ever drawn.
        _ = menuBarEngine
        // A click on the macOS 27 clock expands and collapses the bar as the arrow does.
        if let native = menuBarEngine as? NativeVisibilityEngine {
            native.expandBar = { [weak self] in self?.expandMenubar() }
            native.collapseBar = { [weak self] in self?.collapseMenuBar() }
            native.expandBarForCapture = { [weak self] in self?.expandMenubar(activatingApp: false) }
            pinnedSectionsObserver = NotificationCenter.default.addObserver(forName: .pinnedSectionsChanged, object: nil, queue: .main) { [weak native] _ in
                native?.pinnedSectionsDidChange()
            }
        }
    }

    // macOS 26 can take more than the first second to place the items; the order
    // checks refuse until then, so retry for up to 4 s more, then let them decide.
    private func collapseAtLaunch(retriesLeft: Int) {
        if !menuBarEngine.isArrangementKnown && retriesLeft > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.collapseAtLaunch(retriesLeft: retriesLeft - 1)
            }
            return
        }
        if Preferences.areSeparatorsHidden { hideSeparators() }
        collapseMenuBar()
    }

    // macOS 27: Preferences shows the missing permission, and a grant hides at
    // once instead of after the next click or a relaunch.
    private func watchAccessibilityPermission() {
        let permission = AccessibilityPermission.shared
        permission.onChange = {
            NotificationCenter.default.post(name: .accessibilityPermissionChanged, object: nil)
        }
        permission.onRestored = { [weak self] in self?.collapseMenuBar() }
    }

    private func setupUI() {
        if let button = btnSeparate.button {
            button.image = self.imgIconLine
            button.target = self
            button.action = #selector(self.showContextMenuFromSeparator(sender:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

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
        let event = NSApp.currentEvent
        // AXPress synthesis carries no NSEvent; the resolver maps nil to .toggle
        // so VoiceOver can operate the bar.
        let optionPressed = ExpandCollapseActionResolver.isOptionPressed(eventFlags: event?.modifierFlags, liveFlags: NSEvent.modifierFlags)
        switch ExpandCollapseActionResolver.action(eventType: event?.type, optionPressed: optionPressed) {
        case .toggle:
            self.expandCollapseIfNeeded()
        case .contextMenu:
            // Right-click opens the same context menu the separator has (#356),
            // making settings reachable from the control everyone clicks.
            // The separators/always-hidden toggle stays on option-click.
            showContextMenu(from: sender)
        case .toggleSeparators:
            // Both option+left and option+right land here: separators toggle.
            self.showHideSeparatorsAndAlwayHideArea()
        }
    }

    @objc private func showContextMenuFromSeparator(sender: NSStatusBarButton) {
        showContextMenu(from: sender)
    }

    // Builds a brand-new NSMenu for every presentation rather than mutating
    // a reused one via a delegate callback (content changes on an
    // already-displayed-before NSMenu instance could leave its backing
    // window at a stale size until an unrelated redraw corrected it).
    //
    // Uses popUp(at:), not performClick(nil): this method is ITSELF called
    // from this same button's own action handler (a real click already in
    // progress). performClick(nil) here re-entered NSStatusBarButtonCell's
    // own sendAction dispatch, recursing into this handler again and
    // stack-overflowing (SIGSEGV, confirmed via crash report) - unlike
    // NotchOverflowController.showOverflowMenuFromSeparator, which is safe
    // because it's invoked from a *different* control's action (a menu
    // item), not from btnExpandCollapse's own click handler.
    //
    // Previously anchored at `button.bounds.maxY + 5` (5pt above the
    // button's TOP edge). For a menu-bar item that's essentially the
    // physical top of the screen, so once "Show Notch Items" made the menu
    // one row taller, that top row landed in the sliver above the visible
    // screen and AppKit showed its standard "content doesn't fit here"
    // scroll-indicator caret instead of rendering it - hovering over the
    // indicator scrolled the whole menu into view, which is what looked
    // like the item "appearing on hover". Anchoring at the button's BOTTOM
    // edge instead (y: 0, not bounds.maxY) keeps the menu entirely within
    // on-screen space, growing downward from below the button.
    private func showContextMenu(from button: NSStatusBarButton) {
        let menu = getContextMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: button)
    }
    
    func showHideSeparatorsAndAlwayHideArea() {
        Preferences.areSeparatorsHidden ? self.showSeparators() : self.hideSeparators()
        
        if self.isCollapsed {
            menuBarEngine.userChangedBar()
            self.expandMenubar()
        }
    }
    
    private func showSeparators() {
        Preferences.areSeparatorsHidden = false
        
        if !self.isCollapsed {
            menuBarEngine.expand()
        }
        menuBarEngine.updateAlwaysHiddenSection(enabled: Preferences.alwaysHiddenSectionEnabled, separatorHidden: false)
    }
    
    private func hideSeparators() {
        guard self.isBtnAlwaysHiddenValidPosition else {return}
        
        Preferences.areSeparatorsHidden = true
        
        if !self.isCollapsed {
            menuBarEngine.expand()
        }
        menuBarEngine.updateAlwaysHiddenSection(enabled: Preferences.alwaysHiddenSectionEnabled, separatorHidden: true)
    }
    
    func expandCollapseIfNeeded() {
        //prevented rapid click cause icon show many in Dock
        if isToggle {return}
        isToggle = true
        menuBarEngine.userChangedBar()
        // Without Accessibility the collapse below hides nothing; show the
        // Preferences, which explain what is missing, instead of a dead click.
        if AccessibilityPermission.shared.arrowClickOpensPreferences(isCollapsed: isCollapsed) {
            Util.showPrefWindow()
        }
        self.isCollapsed ? self.expandMenubar() : self.collapseMenuBar()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.isToggle = false
        }
    }
    
    private func collapseMenuBar() {
        guard menuBarEngine.isArrangementValid && !self.isCollapsed else {
            autoCollapseIfNeeded()
            return
        }
        if !Preferences.areSeparatorsHidden
            && menuBarEngine.separatorsHiddenForCollapse(current: Preferences.areSeparatorsHidden) {
            hideSeparators()
        }

        menuBarEngine.collapse { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .collapsed:
                self.didCollapseMenuBar()
            case .unavailable:
                self.didFailToCollapseMenuBar()
            }
        }
    }

    // Nothing was hidden (the engine cannot hide on this system, or is waiting for
    // a permission), so show the bar as expanded, and restore the activation
    // policy in case the UI had already switched to collapsed.
    private func didFailToCollapseMenuBar() {
        if let button = btnExpandCollapse.button {
            button.image = Assets.collapseImage
        }
        if Preferences.useFullStatusBarOnExpandEnabled {
            NSApp.setActivationPolicy(.regular)
        }
    }

    private var collapsedArrowImage: NSImage? {
        Assets.toggleImage(style: Preferences.arrowStyle, isCollapsed: true,
                           stealthEnabled: Preferences.stealthExpandIconEnabled)
    }

    // Applies a stealth or arrow-style change to an arrow that is already on screen.
    @objc private func refreshArrow() {
        btnExpandCollapse.button?.image = isCollapsed ? collapsedArrowImage : Assets.collapseImage
    }

    private func didCollapseMenuBar() {
        if let button = btnExpandCollapse.button {
            button.image = collapsedArrowImage
        }
        if Preferences.useFullStatusBarOnExpandEnabled {
            NSApp.setActivationPolicy(.accessory)
            NSApp.deactivate()
        }
    }

    private func expandMenubar(activatingApp: Bool = true) {
        guard self.isCollapsed else {return}
        menuBarEngine.expand()
        if let button = btnExpandCollapse.button {
            button.image = Assets.collapseImage
        }
        popupGuard.reset()
        autoCollapseIfNeeded()
        
        if activatingApp && Preferences.useFullStatusBarOnExpandEnabled {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            
        }
    }
    
    // Expand/collapse skips the policy change when the option is off, so sync it on toggle.
    @objc private func syncActivationPolicyWithFullStatusBar() {
        let wantsRegular = Preferences.useFullStatusBarOnExpandEnabled && !isCollapsed
        let policy: NSApplication.ActivationPolicy = wantsRegular ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        let keyWindow = NSApp.isActive ? NSApp.keyWindow : nil
        NSApp.setActivationPolicy(policy)
        if wantsRegular {
            NSApp.activate(ignoringOtherApps: true)
        } else if let keyWindow {
            // Dropping to .accessory deactivates the app, so bring back the window in use.
            DispatchQueue.main.async { keyWindow.bringToFront() }
        }
    }

    private func autoCollapseIfNeeded() {
        guard Preferences.isAutoHide else {return}
        guard !isCollapsed else { return }

        startTimerToAutoHide()
    }

    private func startTimerToAutoHide() {
        timer?.invalidate()
        self.timer = Timer.scheduledTimer(withTimeInterval: Preferences.numberOfSecondForAutoHide, repeats: false) { [weak self] _ in
            guard let self = self, Preferences.isAutoHide else { return }
            // Don't yank the bar shut mid-interaction: while the pointer is in the
            // menubar (hovering, clicking, dragging icons), defer and re-arm.
            // Intentionally unbounded; each re-arm invalidates the previous timer,
            // so deferral never accumulates timers. Notification Center opened
            // from the clock collapses the bar itself once it closes. A popup
            // hanging from the menu bar (#319) defers too, for up to 10 minutes;
            // the window list is read last, only when nothing else defers.
            if self.isMouseInMenuBar || self.isPreferencesWindowVisible || self.menuBarEngine.defersAutoCollapse
                || self.popupGuard.defersCollapse() {
                self.startTimerToAutoHide()
            } else {
                self.collapseMenuBar()
            }
        }
    }
    
    // Built fresh on every call (see showContextMenu(from:)), so every field
    // below reflects state as of THIS presentation - no separate "patch the
    // title after the fact" step is needed for the auto-collapse item.
    private func getContextMenu() -> NSMenu {
        let menu = NSMenu()

        // Notch overflow menu item (only on notch Macs, and only when enabled)
        if NotchOverflowController.hasNotch && Preferences.notchOverflowEnabled {
            let overflowItem = NSMenuItem(title: "Show Notch Items".localized, action: #selector(showNotchOverflow), keyEquivalent: "")
            overflowItem.target = self
            menu.addItem(overflowItem)
            menu.addItem(NSMenuItem.separator())
        }

        let prefItem = NSMenuItem(title: "Preferences...".localized, action: #selector(openPreferenceViewControllerIfNeeded), keyEquivalent: "P")
        prefItem.target = self
        menu.addItem(prefItem)

        if menuBarEngine.offersShowEverything {
            let showEverythingItem = NSMenuItem(title: "Show Everything".localized, action: #selector(showEverything), keyEquivalent: "")
            showEverythingItem.target = self
            menu.addItem(showEverythingItem)
        }

        let toggleAutoHideTitle = Preferences.isAutoHide ? "Disable Auto Collapse" : "Enable Auto Collapse"
        let toggleAutoHideItem = NSMenuItem(title: toggleAutoHideTitle.localized, action: #selector(toggleAutoHide), keyEquivalent: "t")
        toggleAutoHideItem.target = self
        menu.addItem(toggleAutoHideItem)

        #if !HIDDENBAR_NATIVE_VISIBILITY
        if let macOS27Item = MacOS27Notice.shared.makeMenuItem() {
            menu.addItem(macOS27Item)
        }
        #endif

        #if HIDDENBAR_SPARKLE
        menu.addItem(UpdateController.shared.makeMenuItem())
        #endif

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit".localized, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        return menu
    }

    @objc func updateAutoHide() {
        autoCollapseIfNeeded()
    }
    
    @objc func openPreferenceViewControllerIfNeeded() {
        Util.showPrefWindow()
    }

    @objc func showNotchOverflow() {
        notchOverflowController.showOverflowMenuFromSeparator(near: btnExpandCollapse)
    }
    
    @objc func toggleAutoHide() {
        Preferences.isAutoHide.toggle()
    }

    // Expands the bar with the always-hidden section shown, until the next
    // collapse hides it again. The way back to icons lost there (#242).
    @objc func showEverything() {
        menuBarEngine.userChangedBar()
        if Preferences.areSeparatorsHidden {
            showSeparators()
        }
        expandMenubar()
    }
}


//MARK: - Alway hide feature
extension StatusBarController {
    private func setupAlwayHideStatusBar() {
        NotificationCenter.default.addObserver(self, selector: #selector(alwaysHiddenSectionToggled), name: .alwayHideToggle, object: nil)
        toggleStatusBarIfNeeded()
    }

    // Turning the section on shows its separator so it can be ⌘-dragged into
    // place; the saved "hide separators" state is reset to match, or the next
    // Option-click would only flip the preference and appear to do nothing.
    @objc private func alwaysHiddenSectionToggled() {
        if Preferences.alwaysHiddenSectionEnabled {
            Preferences.areSeparatorsHidden = false
        }
        toggleStatusBarIfNeeded()
    }

    private func toggleStatusBarIfNeeded() {
        if Preferences.alwaysHiddenSectionEnabled {
            if let existing = self.btnAlwaysHidden {
                NSStatusBar.system.removeStatusItem(existing)
            }
            self.btnAlwaysHidden = NSStatusBar.system.statusItem(withLength: 0)
            if let button = btnAlwaysHidden?.button {
                button.image = self.imgIconLine
                button.appearsDisabled = true
            }
            self.btnAlwaysHidden?.autosaveName = "hiddenbar_terminate"
            self.btnAlwaysHidden?.isVisible = true
            // Last, so the engine decides whether the new item stays in the bar.
            menuBarEngine.updateAlwaysHiddenSection(enabled: true, separatorHidden: false)
        } else {
            if let existing = self.btnAlwaysHidden {
                NSStatusBar.system.removeStatusItem(existing)
            }
            self.btnAlwaysHidden = nil
        }
    }
}

#if DEBUG
//MARK: - Test hooks (Debug builds only)
// Scripted verification on a Mac that is in use: commands arrive as a
// distributed notification, so a harness drives the app with no pointer or key
// input. Never compiled into Release builds.
//
//   name: com.dwarvesv.minimalbar.debug.command
//   userInfo: command, argument (optional), out (path for dump-state JSON)
extension StatusBarController {
    static let debugCommandNotification = Notification.Name("com.dwarvesv.minimalbar.debug.command")

    fileprivate func installDebugHooks() {
        DistributedNotificationCenter.default().addObserver(self,
                                                            selector: #selector(handleDebugCommand(_:)),
                                                            name: Self.debugCommandNotification,
                                                            object: nil,
                                                            suspensionBehavior: .deliverImmediately)
        NSLog("DebugHooks: listening for \(Self.debugCommandNotification.rawValue)")
    }

    @objc private func handleDebugCommand(_ note: Notification) {
        guard let command = note.userInfo?["command"] as? String else { return }
        let argument = note.userInfo?["argument"] as? String
        NSLog("DebugHooks: \(command) \(argument ?? "")")
        switch command {
        case "collapse":
            menuBarEngine.userChangedBar()
            collapseMenuBar()
        case "expand":
            menuBarEngine.userChangedBar()
            expandMenubar()
        case "toggle":
            expandCollapseIfNeeded()
        case "toggle-always-hidden":
            // What Option-click on the arrow runs.
            showHideSeparatorsAndAlwayHideArea()
        case "always-hidden-section":
            // What the Preferences checkbox runs.
            Preferences.alwaysHiddenSectionEnabled = argument == "on"
        case "full-menu-bar":
            // What the Preferences checkbox runs.
            Preferences.useFullStatusBarOnExpandEnabled = argument == "on"
        case "boundary":
            NativeVisibilityEngine.debugBoundaryX = argument.flatMap(Double.init).map { CGFloat($0) }
            menuBarEngine.invalidateLayout()
        case "always-hidden-boundary":
            NativeVisibilityEngine.debugAlwaysHiddenX = argument.flatMap(Double.init).map { CGFloat($0) }
            menuBarEngine.invalidateLayout()
        case "install-location-check":
            NativeVisibilityEngine.debugChecksInstallLocation = argument == "on"
        case "pinned-sections":
            // What the Preferences checkbox runs.
            Preferences.pinnedSectionsEnabled = argument == "on"
        case "pin":
            // What a Preferences "Menu bar apps" row runs: "<bundle id>=visible|hidden|alwaysHidden".
            let parts = (argument ?? "").components(separatedBy: "=")
            let sections: [String: MenuBarSection] = ["visible": .visible, "hidden": .hidden, "alwaysHidden": .alwaysHidden]
            if parts.count == 2, let section = sections[parts[1]] {
                PinnedSectionEdits.set(section, for: parts[0], in: UserDefaultsPinnedSections())
            }
        case "reset-pinned":
            // What the Preferences "Reset all to visible" button runs.
            PinnedSectionEdits.resetAllToVisible(in: UserDefaultsPinnedSections())
        case "show-everything":
            // What the arrow menu's "Show Everything" runs.
            showEverything()
        case "click-clock":
            debugClickClock(pressingWithAX: argument == "ax")
        case "dump-state":
            break
        default:
            NSLog("DebugHooks: unknown command \(command)")
        }
        if let out = note.userInfo?["out"] as? String {
            debugWriteState(to: out)
        }
    }

    // A click on the clock without moving the pointer: the mouse-down/up pair is
    // posted to MenuBarAgent's process only, then the engine's clock-click
    // handler runs exactly as its global mouse monitor would call it.
    // With "ax", the engine replays the press with AXPress, which opens the panel.
    private func debugClickClock(pressingWithAX: Bool) {
        guard let (pid, clock) = Self.debugClock() else {
            return NSLog("DebugHooks: clock not found")
        }
        let center = CGPoint(x: clock.midX, y: clock.midY)
        Self.debugPostClick(at: center, toPid: pid)
        (menuBarEngine as? NativeVisibilityEngine)?.debugClockClicked(at: center, postingTo: pid, pressingWithAX: pressingWithAX)
    }

    static func debugPostClick(at point: CGPoint, toPid pid: pid_t) {
        guard let source = CGEventSource(stateID: .privateState) else { return }
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { return }
            event.flags = []
            event.setIntegerValueField(.mouseEventClickState, value: 1)
            event.postToPid(pid)
        }
    }

    static func debugClock() -> (pid_t, CGRect)? {
        guard let agent = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.MenuBarAgent").first else { return nil }
        let app = AXUIElementCreateApplication(agent.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.5)
        func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
            var value: CFTypeRef?
            return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
        }
        func children(_ element: AXUIElement) -> [AXUIElement] {
            return value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
        }
        guard let bar = value(app, "AXExtrasMenuBar") else { return nil }
        for group in children(bar as! AXUIElement) {
            for item in [group] + children(group) where value(item, "AXIdentifier") as? String == "com.apple.menuextra.clock" {
                if let frame = AccessibilityMenuBarInventory.frame(of: item) {
                    return (agent.processIdentifier, frame)
                }
            }
        }
        return nil
    }

    private func debugWriteState(to path: String) {
        let policies: [NSApplication.ActivationPolicy: String] = [.regular: "regular", .accessory: "accessory", .prohibited: "prohibited"]
        var state: [String: Any] = [
            "engine": String(describing: type(of: menuBarEngine)),
            "state": String(describing: menuBarEngine.state),
            "activationPolicy": policies[NSApp.activationPolicy()] ?? "unknown",
            "useFullStatusBarOnExpand": Preferences.useFullStatusBarOnExpandEnabled,
            "alwaysHiddenSectionEnabled": Preferences.alwaysHiddenSectionEnabled,
            "areSeparatorsHidden": Preferences.areSeparatorsHidden,
            "alwaysHiddenItemVisible": btnAlwaysHidden?.isVisible ?? false,
            "arrowFrame": btnExpandCollapse.button?.window.map { NSStringFromRect($0.frame) } ?? "none",
            "alwaysHiddenSeparatorFrame": btnAlwaysHidden?.button?.window.map { NSStringFromRect($0.frame) } ?? "none",
            "writtenAt": Date().timeIntervalSince1970
        ]
        if let engine = menuBarEngine as? NativeVisibilityEngine {
            state.merge(engine.debugState) { $1 }
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: path))
        } catch {
            NSLog("DebugHooks: cannot write state: \(error.localizedDescription)")
        }
    }
}
#endif
