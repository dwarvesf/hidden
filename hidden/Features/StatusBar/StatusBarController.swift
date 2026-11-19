//
//  StatusBarController.swift
//  vanillaClone
//
//  Created by Thanh Nguyen on 1/30/19.
//  Copyright © 2019 Console Labs. All rights reserved.
//

import AppKit

class StatusBarController: MenuBarItemProvider {
    
    //MARK: - Variables
    private var timer:Timer? = nil
    private var autoCollapseAttempts = 0
    private var wasAutoHideEnabled = false
    private static let autoCollapseAttemptLimit = 3
    private let engineFactory: (MenuBarItemProvider) -> MenuBarEngine
    private let scheduleAutoHide: (TimeInterval, @escaping () -> Void) -> Timer
    private let autoHideDeferral: (() -> Bool)?
    private let noHideNotice: NoHideNoticePresenting?
    private var noHidePolicy = NoHideNoticePolicy()

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
    private lazy var menuBarEngine: MenuBarEngine = engineFactory(self)

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

    #if HIDDENBAR_NATIVE_VISIBILITY
    // Presentation mode (macOS 27, direct build): the capsule, the manual switch
    // and the mirror trigger. Nil where the native engine does not run.
    private var presentationController: PresentationController?
    #endif

    // Reveal without aiming: scroll, click on empty space, pointer shake.
    private lazy var revealController = RevealController(
        host: RevealHost(
            isCollapsed: { [weak self] in self?.isCollapsed ?? false },
            isOwnMenuOpen: { [weak self] in self?.isShowingOwnMenu ?? false },
            show: { [weak self] in
                self?.menuBarEngine.userChangedBar()
                self?.expandMenubar()
            },
            hide: { [weak self] in
                self?.menuBarEngine.userChangedBar()
                self?.collapseMenuBar(userInitiated: true)
            },
            hideOffMenuBar: { [weak self] in
                guard let self = self, !self.defersCollapseApartFromPointer else { return }
                self.menuBarEngine.userChangedBar()
                self.collapseMenuBar()
            }),
        isEnabled: { trigger in
            switch trigger {
            case .scroll: return Preferences.revealOnScrollEnabled
            case .click: return Preferences.revealOnEmptyClickEnabled
            case .shake: return Preferences.revealOnShakeEnabled
            }
        },
        isSuspended: { [weak self] in self?.isPresenting ?? false },
        screens: ScreenBand.live)
    // Tests stand in for presentation mode, which would hold a real restriction.
    var presentingOverride: Bool?
    // True while the arrow's context menu is up.
    private var isShowingOwnMenu = false

    // Presentation mode is on: the reveal gestures and the arrivals question stay
    // quiet, since the room sees the screen.
    private var isPresenting: Bool {
        #if HIDDENBAR_NATIVE_VISIBILITY
        if let presentingOverride { return presentingOverride }
        return presentationController?.isOn ?? false
        #else
        return false
        #endif
    }

    #if HIDDENBAR_NATIVE_VISIBILITY
    // Asks about apps that add a first icon (Ask Me), from the arrow.
    private lazy var arrivalsPresenter = ArrivalsPresenter(isSuppressed: { [weak self] in self?.isPresenting ?? false }, openSettings: {
        Util.showPrefWindow()
        PreferencesWindowController.shared.select(.menuBarApps)
    })
    private var arrivalsObserver: NSObjectProtocol?
    // The type-to-find palette (direct build, native engine). Built on first use.
    private var paletteSession: PaletteRevealSession?
    private lazy var palette: PaletteController = makePalette()
    #endif

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
    // when preferences were never opened. With the option off nothing is
    // dismissed, so the window must not hold auto-hide.
    private var isPreferencesWindowVisible: Bool {
        return wantsFullBar && PreferencesWindowController.isVisible
    }
    
    //MARK: - Methods
    init(engineFactory: @escaping (MenuBarItemProvider) -> MenuBarEngine = { MenuBarEngineFactory.make(items: $0) },
         scheduleAutoHide: @escaping (TimeInterval, @escaping () -> Void) -> Timer = { delay, fire in
             Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in fire() }
         },
         autoHideDeferral: (() -> Bool)? = nil,
         noHideNotice: NoHideNoticePresenting? = nil) {
        self.engineFactory = engineFactory
        self.scheduleAutoHide = scheduleAutoHide
        self.autoHideDeferral = autoHideDeferral
        #if HIDDENBAR_NATIVE_VISIBILITY
        self.noHideNotice = noHideNotice ?? ArrowNoticePresenter()
        #else
        self.noHideNotice = noHideNotice
        #endif
        setupUI()
        restoreRemovedStatusItems()
        setupAlwayHideStatusBar()
        syncHoverToExpand()
        revealController.sync()
        NotificationCenter.default.addObserver(self, selector: #selector(syncHoverToExpand), name: .prefsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(syncReveal), name: .prefsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleScreenParametersChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateAutoHide), name: .prefsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(syncActivationPolicyWithFullStatusBar), name: .useFullStatusBarToggle, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshArrow), name: .stealthExpandIconToggle, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshArrow), name: .arrowStyleChanged, object: nil)
        watchAccessibilityPermission()
        startArrivals()
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
        timer?.invalidate()
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
    
    // Same rule as hover: monitors exist only while their pref is on.
    @objc private func syncReveal() {
        revealController.sync()
    }

    @objc private func handleScreenParametersChanged() {
        // Re-apply the recomputed length to the LIVE item when collapsed, or a
        // display hot-plug leaves the separator at a stale length (PR #354).
        let wasCollapsed = isCollapsed
        menuBarEngine.invalidateLayout()
        #if HIDDENBAR_NATIVE_VISIBILITY
        presentationController?.syncMirror()
        #endif
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
            native.onUserChangedBar = { [weak self] in
                #if HIDDENBAR_NATIVE_VISIBILITY
                self?.paletteSession?.userChangedBar()
                #endif
            }
            #if HIDDENBAR_NATIVE_VISIBILITY
            presentationController = PresentationController(engine: native, arrowButton: { [weak self] in self?.btnExpandCollapse.button })
            #endif
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
        #if HIDDENBAR_NATIVE_VISIBILITY
        // A display already mirrored at launch starts presentation mode now that
        // the items are placed, so the first collapse already holds the strict list.
        presentationController?.syncMirror()
        #endif
        collapseMenuBar(automatic: Preferences.isAutoHide)
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
        
        // macOS persists an autosaved item's position and visibility in the app's
        // preferences domain, so a test host leaves its items unnamed.
        if AppDefaults.allowsHostSideEffects {
            btnExpandCollapse.autosaveName = "hiddenbar_expandcollapse";
            btnSeparate.autosaveName = "hiddenbar_separate";
        }
    }
    
    @objc func btnExpandCollapsePressed(sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        // AXPress synthesis carries no NSEvent; the resolver maps nil to .toggle
        // so VoiceOver can operate the bar.
        let optionPressed = ExpandCollapseActionResolver.isOptionPressed(eventFlags: event?.modifierFlags, liveFlags: NSEvent.modifierFlags)
        let shiftPressed = ExpandCollapseActionResolver.isShiftPressed(eventFlags: event?.modifierFlags, liveFlags: NSEvent.modifierFlags)
        let action = ExpandCollapseActionResolver.action(eventType: event?.type, optionPressed: optionPressed, shiftPressed: shiftPressed,
                                                         rightClick: Preferences.rightClickAction)
        if action.closesArrowPopovers { closeArrowPopovers() }
        switch action {
        case .ignore:
            break
        case .toggle:
            let wasCollapsed = isCollapsed
            self.expandCollapseIfNeeded()
            if wasCollapsed && action.mayShowArrivalsPrompt { showArrivalsIfWaiting() }
        case .toggleWithFullBar:
            // Shift-click expands with the full menu bar for this expansion only;
            // the stored setting is untouched. Collapsing works as a plain click.
            self.expandCollapseIfNeeded(fullBarOnce: true)
        case .contextMenu:
            // Right-click opens the same context menu the separator has (#356),
            // making settings reachable from the control everyone clicks.
            // The separators/always-hidden toggle stays on option-click.
            // With right-click set to the always-hidden icons, Option-right-click.
            showContextMenu(from: sender)
        case .toggleSeparators:
            // Option-click lands here, and a plain right-click when the user
            // picked "Show always-hidden icons" for it.
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
        isShowingOwnMenu = true
        defer { isShowingOwnMenu = false }
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
    
    func expandCollapseIfNeeded(fullBarOnce: Bool = false) {
        //prevented rapid click cause icon show many in Dock
        if isToggle {return}
        isToggle = true
        if fullBarOnce && isCollapsed { fullBarThisExpansion = true }
        menuBarEngine.userChangedBar()
        // Without Accessibility the collapse below hides nothing; show the
        // Preferences, which explain what is missing, instead of a dead click.
        if AccessibilityPermission.shared.arrowClickOpensPreferences(isCollapsed: isCollapsed) {
            Util.showPrefWindow()
        }
        self.isCollapsed ? self.expandMenubar(userInitiated: true) : self.collapseMenuBar(userInitiated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.isToggle = false
        }
    }
    
    private func collapseMenuBar(userInitiated: Bool = false, automatic: Bool = false) {
        guard !isCollapsed else { return }
        guard menuBarEngine.isArrangementValid && menuBarEngine.state != .calibrating else {
            if automatic { autoCollapseIfNeeded() }
            return
        }
        if automatic {
            guard syncAutoHideState(), autoCollapseAttempts < Self.autoCollapseAttemptLimit else { return }
            autoCollapseAttempts += 1
            timer?.invalidate()
            timer = nil
        }
        if !Preferences.areSeparatorsHidden
            && menuBarEngine.separatorsHiddenForCollapse(current: Preferences.areSeparatorsHidden) {
            hideSeparators()
        }

        menuBarEngine.collapse { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .collapsed, .collapsedNothingHidden:
                self.didCollapseMenuBar(userInitiated: userInitiated)
            case .unavailable, .refused:
                self.didFailToCollapseMenuBar()
                if automatic { self.autoCollapseIfNeeded() }
            }
            self.explainNothingHidden(result, userInitiated: userInitiated)
        }
    }

    // A click that hid nothing says why, once per reason. A timer attempt stays
    // quiet: it retries by itself and the user did not ask.
    private func explainNothingHidden(_ result: CollapseResult, userInitiated: Bool) {
        guard let reason = result.noHideReason, let notice = noHideNotice,
              noHidePolicy.shouldShow(reason, userInitiated: userInitiated, isNoticeShowing: notice.isShown),
              notice.show(reason, from: btnExpandCollapse.button) else { return }
        noHidePolicy.recordShown(reason)
    }

    // Nothing was hidden (the engine cannot hide on this system, or is waiting for
    // a permission), so show the bar as expanded, and restore the activation
    // policy in case the UI had already switched to collapsed.
    // Set by a Shift-click expansion; didCollapseMenuBar clears it.
    private var fullBarThisExpansion = false

    private var wantsFullBar: Bool {
        return Preferences.useFullStatusBarOnExpandEnabled || fullBarThisExpansion
    }

    private func didFailToCollapseMenuBar() {
        if let button = btnExpandCollapse.button {
            button.image = Assets.collapseImage
        }
        if wantsFullBar {
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

    private func didCollapseMenuBar(userInitiated: Bool) {
        autoCollapseAttempts = 0
        timer?.invalidate()
        timer = nil
        if let button = btnExpandCollapse.button {
            button.image = collapsedArrowImage
        }
        if wantsFullBar {
            NSApp.setActivationPolicy(.accessory)
            NSApp.deactivate()
        }
        fullBarThisExpansion = false
        revealController.barDidCollapse()
        #if HIDDENBAR_NATIVE_VISIBILITY
        if userInitiated {
            SystemOverflowNotice.shared.checkAfterCollapse(arrow: btnExpandCollapse,
                                                           isCollapsed: { [weak self] in self?.isCollapsed ?? false })
        }
        #endif
    }

    private func expandMenubar(activatingApp: Bool = true, userInitiated: Bool = false) {
        guard self.isCollapsed else {return}
        #if HIDDENBAR_NATIVE_VISIBILITY
        // Read before the engine expands: it is what the bar hid until now.
        let hiddenBundles = userInitiated ? menuBarEngine.hiddenSectionBundles : []
        #endif
        menuBarEngine.expand()
        autoCollapseAttempts = 0
        if let button = btnExpandCollapse.button {
            button.image = Assets.collapseImage
        }
        popupGuard.reset()
        loggedCollapseHolds.removeAll()
        autoCollapseIfNeeded()
        
        if activatingApp && wantsFullBar {
            NSApp.setActivationPolicy(.regular)
            FullBarActivation.activate(NSApp)
        }
        #if HIDDENBAR_NATIVE_VISIBILITY
        presentationController?.barExpanded()
        if userInitiated {
            SystemOverflowNotice.shared.checkAfterExpand(hiddenBundles: hiddenBundles,
                                                         isExpanded: { [weak self] in !(self?.isCollapsed ?? true) })
        }
        #endif
    }
    
    // Expand/collapse skips the policy change when the option is off, so sync it on toggle.
    @objc private func syncActivationPolicyWithFullStatusBar() {
        let wantsRegular = wantsFullBar && !isCollapsed
        let policy: NSApplication.ActivationPolicy = wantsRegular ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        let keyWindow = NSApp.isActive ? NSApp.keyWindow : nil
        NSApp.setActivationPolicy(policy)
        if wantsRegular {
            FullBarActivation.activate(NSApp)
        } else if let keyWindow {
            // Dropping to .accessory deactivates the app, so bring back the window in use.
            DispatchQueue.main.async { keyWindow.bringToFront() }
        }
    }

    private func syncAutoHideState() -> Bool {
        let enabled = Preferences.isAutoHide
        if enabled && !wasAutoHideEnabled { autoCollapseAttempts = 0 }
        wasAutoHideEnabled = enabled
        return enabled
    }

    private func autoCollapseIfNeeded() {
        guard syncAutoHideState(), !isCollapsed,
              autoCollapseAttempts < Self.autoCollapseAttemptLimit else {
            timer?.invalidate()
            timer = nil
            return
        }

        startTimerToAutoHide()
    }

    // What holds an auto-collapse back besides the pointer sitting in the menu bar.
    // A popup hanging from the menu bar (#319) defers for up to 10 minutes; the
    // window list is read last, only when nothing else defers.
    private var defersCollapseApartFromPointer: Bool {
        return holdsCollapse("AutoCollapse: holding for the Settings window", if: isPreferencesWindowVisible)
            || holdsCollapse("AutoCollapse: holding for the new-apps prompt", if: arrivalsPromptIsShown)
            || holdsCollapse("AutoCollapse: holding for Notification Center", if: menuBarEngine.defersAutoCollapse)
            || holdsCollapse("AutoCollapse: holding for the palette", if: isRevealingForPalette)
            || popupGuard.defersCollapse()
    }

    // Holds already logged since the bar last expanded, so a hold that lasts
    // many timer fires logs once. The line is a StaticString and goes to the
    // public log: only the reason, never window titles.
    private var loggedCollapseHolds = Set<String>()

    // The condition is evaluated lazily, so the order and short-circuit of the
    // callers do not change.
    private func holdsCollapse(_ line: StaticString, if condition: @autoclosure () -> Bool) -> Bool {
        guard condition() else { return false }
        if loggedCollapseHolds.insert("\(line)").inserted {
            AppLog.publicLine(line)
        }
        return true
    }

    // The palette has an app's menu open that it allowed for a moment.
    private var isRevealingForPalette: Bool {
        #if HIDDENBAR_NATIVE_VISIBILITY
        return paletteSession?.isActive ?? false
        #else
        return false
        #endif
    }

    private func startTimerToAutoHide() {
        timer?.invalidate()
        self.timer = scheduleAutoHide(Preferences.numberOfSecondForAutoHide) { [weak self] in
            guard let self = self, Preferences.isAutoHide else { return }
            // Don't yank the bar shut mid-interaction: while the pointer is in the
            // menubar (hovering, clicking, dragging icons), defer and re-arm.
            // Intentionally unbounded; each re-arm invalidates the previous timer,
            // so deferral never accumulates timers. Notification Center opened
            // from the clock collapses the bar itself once it closes. A popup
            // hanging from the menu bar (#319) defers too, for up to 10 minutes;
            // the window list is read last, only when nothing else defers.
            let shouldDefer = self.autoHideDeferral?()
                ?? (self.holdsCollapse("AutoCollapse: holding for the pointer in the menu bar", if: self.isMouseInMenuBar)
                    || self.defersCollapseApartFromPointer)
            if shouldDefer {
                self.startTimerToAutoHide()
            } else {
                self.collapseMenuBar(automatic: true)
            }
        }
    }
    
    // Built fresh on every call (see showContextMenu(from:)), so every field
    // below reflects state as of THIS presentation - no separate "patch the
    // title after the fact" step is needed for the auto-collapse item.
    private func getContextMenu() -> NSMenu {
        let menu = NSMenu()

        // Notch overflow menu item (only where icons can hide behind a notch, and only when enabled)
        if NotchOverflowSupport.isAvailableNow && Preferences.notchOverflowEnabled {
            let overflowItem = NSMenuItem(title: "Show Notch Items".localized, action: #selector(showNotchOverflow), keyEquivalent: "")
            overflowItem.target = self
            menu.addItem(overflowItem)
            menu.addItem(NSMenuItem.separator())
        }

        #if HIDDENBAR_NATIVE_VISIBILITY
        if let findItem = makeFindHiddenIconMenuItem() {
            menu.addItem(findItem)
        }
        #endif

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

        #if HIDDENBAR_NATIVE_VISIBILITY
        if let presentation = presentationController {
            menu.addItem(NSMenuItem.separator())
            let presentationItem = NSMenuItem(title: presentation.menuTitle, action: #selector(togglePresentationMode), keyEquivalent: "")
            presentationItem.target = self
            presentationItem.setShortcut(HotKeyRegistry.shared.shortcut(for: UserDefaults.Key.presentationShortcut))
            menu.addItem(presentationItem)
            menu.addItem(NSMenuItem.separator())
        }
        #endif

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

    #if HIDDENBAR_NATIVE_VISIBILITY
    // The shortcut, the arrow menu item and the debug hook all run this.
    @objc func togglePresentationMode() {
        presentationController?.toggle()
    }
    #endif

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


#if HIDDENBAR_NATIVE_VISIBILITY
//MARK: - Type-to-find palette
extension StatusBarController {
    // The shortcut and the arrow's menu item both land here.
    func togglePalette() {
        guard MenuBarEngineFactory.usesNativeEngine() else { return }
        palette.toggle()
    }

    @objc private func findHiddenIcon() {
        palette.show()
    }

    // The arrow menu's way in, shown only while the shortcut is set: unset, the
    // feature is off.
    fileprivate func makeFindHiddenIconMenuItem() -> NSMenuItem? {
        guard MenuBarEngineFactory.usesNativeEngine(), let shortcut = Preferences.findHiddenIconShortcut else { return nil }
        let item = NSMenuItem(title: "Find a Hidden Icon...".localized, action: #selector(findHiddenIcon), keyEquivalent: "")
        item.target = self
        if let key = shortcut.characters?.lowercased(), key.count == 1 {
            item.keyEquivalent = key
            var mask: NSEvent.ModifierFlags = []
            if shortcut.command { mask.insert(.command) }
            if shortcut.option { mask.insert(.option) }
            if shortcut.control { mask.insert(.control) }
            if shortcut.shift { mask.insert(.shift) }
            item.keyEquivalentModifierMask = mask
        }
        return item
    }

    /// What the palette reads each time it opens or refreshes. While presenting it
    /// carries the sensitive apps, which the palette leaves out of its list.
    func paletteEnvironment() -> PaletteEnvironment {
        return PaletteEnvironment(accessibilityTrusted: !AccessibilityPermission.shared.isMissing,
                                  engineAvailable: menuBarEngine.state != .unavailable,
                                  pinsSections: Preferences.pinnedSectionsEnabled,
                                  hiddenWhilePresenting: isPresenting ? Preferences.presentationSensitiveApps : [])
    }

    fileprivate func makePalette() -> PaletteController {
        let session = PaletteRevealSession(
            now: { ProcessInfo.processInfo.systemUptime },
            after: { delay, step in DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: step) },
            allow: { [weak self] bundle, done in
                guard let self = self else { return done(.unavailable) }
                self.menuBarEngine.allowTemporarily(bundle, completion: done)
            },
            press: { bundle, done in PaletteItemPresser.press(bundle: bundle, completion: done) },
            menuIsOpen: { PaletteItemPresser.isMenuOpen(bundle: $0) },
            appIsActive: { PaletteItemPresser.isActive(bundle: $0) },
            restore: { [weak self] in self?.menuBarEngine.endTemporaryAllow() })
        paletteSession = session
        let host = PaletteHost(
            environment: { [weak self] in self?.paletteEnvironment() ?? PaletteEnvironment(accessibilityTrusted: false, engineAvailable: false) },
            arrowFrame: { [weak self] in self?.btnExpandCollapse.button?.window?.frame },
            open: { bundle, done in session.open(bundle: bundle, completion: done) },
            move: { section, bundle in PinnedSectionEdits.set(section, for: bundle, in: UserDefaultsPinnedSections()) },
            openAccessibilitySettings: { AccessibilityPermission.openSystemSettings() },
            openMenuBarApps: {
                Util.showPrefWindow()
                PreferencesWindowController.shared.select(.menuBarApps)
            })
        return PaletteController(host: host)
    }
}
#endif

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
            if AppDefaults.allowsHostSideEffects {
                self.btnAlwaysHidden?.autosaveName = "hiddenbar_terminate"
            }
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
        case "toggle-full-bar-once":
            // What Shift-click on the arrow runs.
            expandCollapseIfNeeded(fullBarOnce: true)
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
        case "drag-lock":
            // What a Menu Bar Apps row's "Ignore drags" checkbox runs: "<bundle id>=on|off".
            let parts = (argument ?? "").components(separatedBy: "=")
            if parts.count == 2 {
                LiveMenuBarAppsStore().setIgnoresDrags(parts[1] == "on", for: parts[0])
            }
        case "settings":
            // Shows Settings on a tab without activating the app: "<tab>[,light|dark][,<bundle id>]",
            // the bundle's Menu Bar Apps row scrolled into view; "close" closes it.
            debugShowSettings(argument ?? "")
        case "show-everything":
            // What the arrow menu's "Show Everything" runs.
            showEverything()
        case "click-clock":
            debugClickClock(pressingWithAX: argument == "ax")
        case "present":
            // What the shortcut and the arrow menu item run: "on", "off" or "toggle".
            #if HIDDENBAR_NATIVE_VISIBILITY
            switch argument {
            case "on": presentationController?.start()
            case "off": presentationController?.stop()
            default: presentationController?.toggle()
            }
            #endif
        case "reveal-sim":
            // What a real scroll, click or shake runs: "scroll", "scroll-up", "click" or "shake".
            revealController.simulate(argument ?? "")
        case "arrivals-inject":
            // Asks about a bundle as if a read had just found it: "<bundle id>".
            if let argument { debugArrivalsInject(argument) }
        case "arrivals-answer":
            // What a prompt button runs: "<bundle id>=show|hide".
            debugArrivalsAnswer(argument ?? "")
        case "arrivals-prompt":
            // Opens the prompt under the arrow, as a click on it does while something waits.
            showArrivalsIfWaiting()
        case "dump-state":
            break
        case "palette-open", "palette-query", "palette-select", "palette-activate", "palette-close":
            debugPalette(command, argument: argument)
        case "dump-inventory":
            // The menu-bar app catalog as JSON in `out`, instead of the state dump.
            debugWriteInventory(to: note.userInfo?["out"] as? String)
            return
        default:
            NSLog("DebugHooks: unknown command \(command)")
        }
        if let out = note.userInfo?["out"] as? String {
            debugWriteState(to: out)
        }
    }

    // Ordered front without activating, so the user's frontmost app keeps the
    // keyboard; drawn as the key window, as the snapshots are.
    private func debugShowSettings(_ argument: String) {
        let parts = argument.components(separatedBy: ",")
        let controller = PreferencesWindowController.shared
        guard let window = controller.window as? SettingsWindow else { return }
        if parts[0] == "close" {
            window.drawsAsKey = false
            return window.close()
        }
        if let tab = SettingsTab(rawValue: parts[0]) {
            controller.select(tab, animate: false)
        }
        let appearances: [String: NSAppearance.Name] = ["light": .aqua, "dark": .darkAqua]
        window.appearance = parts.count > 1 ? appearances[parts[1]].flatMap { NSAppearance(named: $0) } : nil
        window.drawsAsKey = true
        window.orderFrontRegardless()
        if parts.count > 2, let row = Self.debugView(in: window.contentView,
                                                     identifier: MenuBarAppsSettingsViewController.lockIdentifier(for: parts[2])) {
            row.scrollToVisible(row.bounds)
        }
        window.display()
    }

    static func debugView(in view: NSView?, identifier: String) -> NSView? {
        guard let view else { return nil }
        if view.identifier?.rawValue == identifier { return view }
        return view.subviews.lazy.compactMap { debugView(in: $0, identifier: identifier) }.first
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

    // The palette hooks (direct build): "palette-open" shows it on the display with
    // the pointer without activating the app, "palette-query <text>" types for you,
    // "palette-select <bundle id>" moves the selection, "palette-activate
    // open|keep|hide" is Return, Command-Return or Option-Return, "palette-close".
    private func debugPalette(_ command: String, argument: String?) {
        #if HIDDENBAR_NATIVE_VISIBILITY
        switch command {
        case "palette-open": palette.show(query: argument ?? "")
        case "palette-query": palette.setQuery(argument ?? "")
        case "palette-select": palette.select(bundle: argument ?? "")
        case "palette-activate":
            let actions: [String: PaletteKeyAction] = ["open": .open, "keep": .keepShown, "hide": .alwaysHide]
            palette.perform(actions[argument ?? "open"] ?? .open)
        default: palette.close()
        }
        #else
        NSLog("DebugHooks: the palette is a direct-build feature")
        #endif
    }

    private func debugWriteInventory(to path: String?) {
        guard let path else { return NSLog("DebugHooks: dump-inventory needs --out") }
        #if HIDDENBAR_NATIVE_VISIBILITY
        let data = try? MenuBarItemCatalog.shared.debugJSON()
        #else
        // The catalog is a direct-build feature; say so rather than leave the caller waiting.
        let data = try? JSONSerialization.data(withJSONObject: ["entries": [], "arrivals": [], "available": false] as [String: Any],
                                               options: [.prettyPrinted, .sortedKeys])
        #endif
        do {
            try (data ?? Data()).write(to: URL(fileURLWithPath: path))
        } catch {
            NSLog("DebugHooks: cannot write inventory: \(error.localizedDescription)")
        }
    }

    private func debugWriteState(to path: String) {
        let policies: [NSApplication.ActivationPolicy: String] = [.regular: "regular", .accessory: "accessory", .prohibited: "prohibited"]
        var state: [String: Any] = [
            "engine": String(describing: type(of: menuBarEngine)),
            "state": String(describing: menuBarEngine.state),
            "activationPolicy": policies[NSApp.activationPolicy()] ?? "unknown",
            "useFullStatusBarOnExpand": Preferences.useFullStatusBarOnExpandEnabled,
            "fullBarThisExpansion": fullBarThisExpansion,
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
        state.merge(revealController.debugState) { $1 }
        state.merge(debugArrivalsState) { $1 }
        #if HIDDENBAR_NATIVE_VISIBILITY
        state["palette"] = palette.debugState
        state["paletteSession"] = paletteSession?.debugState ?? ["active": false]
        #endif
        do {
            let data = try JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: path))
        } catch {
            NSLog("DebugHooks: cannot write state: \(error.localizedDescription)")
        }
    }
}
#endif

//MARK: - Arrivals
// Kept apart from the rest of the controller: it is the only part of this file
// the arrivals inbox touches.
extension StatusBarController {
    fileprivate func startArrivals() {
        #if HIDDENBAR_NATIVE_VISIBILITY
        guard MenuBarEngineFactory.usesNativeEngine() else { return }
        ArrivalsController.shared.start()
        arrivalsObserver = NotificationCenter.default.addObserver(forName: .arrivalsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.syncArrivalsDot()
        }
        syncArrivalsDot()
        #endif
    }

    fileprivate func syncArrivalsDot() {
        #if HIDDENBAR_NATIVE_VISIBILITY
        ArrivalsArrowDot.sync(on: btnExpandCollapse.button, visible: !ArrivalsController.shared.pending.isEmpty)
        #endif
    }

    fileprivate func showArrivalsIfWaiting() {
        #if HIDDENBAR_NATIVE_VISIBILITY
        arrivalsPresenter.present(from: btnExpandCollapse.button)
        #endif
    }

    // The arrivals prompt and the presentation note hang from the arrow.
    fileprivate func closeArrowPopovers() {
        noHideNotice?.close()
        #if HIDDENBAR_NATIVE_VISIBILITY
        arrivalsPresenter.close()
        presentationController?.closeNote()
        #endif
    }

    fileprivate var arrivalsPromptIsShown: Bool {
        #if HIDDENBAR_NATIVE_VISIBILITY
        return arrivalsPresenter.isShown
        #else
        return false
        #endif
    }
}

#if DEBUG
extension StatusBarController {
    fileprivate func debugArrivalsInject(_ bundle: String) {
        #if HIDDENBAR_NATIVE_VISIBILITY
        ArrivalsController.shared.debugInject(bundle)
        #endif
    }

    fileprivate func debugArrivalsAnswer(_ argument: String) {
        #if HIDDENBAR_NATIVE_VISIBILITY
        let parts = argument.components(separatedBy: "=")
        let answers: [String: ArrivalAnswer] = ["show": .show, "hide": .hide, "always-hide": .alwaysHide]
        if parts.count == 2, let answer = answers[parts[1]] {
            ArrivalsController.shared.answer(parts[0], answer)
        }
        #endif
    }

    fileprivate var debugArrivalsState: [String: Any] {
        #if HIDDENBAR_NATIVE_VISIBILITY
        var state = ArrivalsController.shared.debugState
        state["arrivalsPromptShown"] = arrivalsPresenter.isShown
        state["arrivalsDot"] = btnExpandCollapse.button?.subviews.contains { $0 is ArrivalsArrowDot } ?? false
        return state
        #else
        return [:]
        #endif
    }
}
#endif
