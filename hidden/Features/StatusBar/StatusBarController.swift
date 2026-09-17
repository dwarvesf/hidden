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

    // Serial number of the newest length ramp per status item; any later length change
    // to the same item bumps it, which makes an in-flight ramp stop on its next step.
    private var lengthRampGenerations: [ObjectIdentifier: Int] = [:]

    // The collapse length PROVEN to hide on the current display configuration, or nil
    // while that is still unknown.
    //
    // macOS27CollapseLength() derives a length from the half-a-display cliff, but that
    // cliff has only been measured on two display widths. Where the arithmetic is wrong
    // the separator is ejected from the layout again and hiding silently stops, which is
    // #360 all over again on a display nobody tested.
    //
    // Nothing about the separator itself reveals the ejection. It reports whatever length
    // it was given; its origin moves in both cases; and its arrow-facing edge starts
    // moving well BELOW the cliff, because the item clamps against the status region's
    // left edge and then grows out past the arrow. Measured on 27.0 (26A428), 1728pt
    // display, with foreign icons in the hidden zone as the ground truth:
    //
    //     length  arrow-facing edge moved   icons actually hidden
    //      400pt                     0pt    yes
    //      600pt                   200pt    yes
    //      840pt                   440pt    yes
    //      900pt                   500pt    NO  <- the real cliff is between 840 and 900
    //
    // So an edge-jump test reads 600pt as a failure on a bar that is hiding correctly.
    //
    // What IS observable in-process is one of our OWN items sitting in the hidden zone. A
    // status item registered last lands leftmost, so a temporary canary registered while
    // the bar is expanded takes a slot among the icons this collapse has to clear, and
    // what it does next answers the question the separator cannot: an honored length
    // carries it to the region's left edge, an ejected one leaves it where it sat. The
    // signal is that TRAVEL, not the position it ends at -- when the separator clamps
    // against the region's left edge, a canary holding a live slot and a parked one come
    // to rest within a few points of each other.
    //
    // The canary must be allowed to SEAT before the separator grows. macOS 27 will not
    // evict a seated neighbour (the reason growth is ramped, see setLength), but a
    // freshly registered item yields to the separator's claimed span whether or not that
    // span is honored: measured at 0.35s the canary travelled on a 964pt request that hid
    // nothing, and at 1.0s it correctly stayed put and the retry found 723pt.
    private var honoredCollapseLength: CGFloat?
    private var isVerifyingHideMechanism = false
    private var canaryItem: NSStatusItem?
    private var canaryRestingOrigin: CGFloat?

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
        // The cliff is a property of the display, so a hot-plug retires whatever was
        // proven for the previous configuration; the next collapse verifies again.
        honoredCollapseLength = nil
        if wasCollapsed {
            setLength(btnSeparate, to: btnHiddenCollapseLength)
            if Preferences.areSeparatorsHidden, let alwaysHidden = btnAlwaysHidden {
                setLength(alwaysHidden, to: alwaysHiddenCollapseLength())
            }
        }
    }

    private func updateCollapsedLengths() {
        let boundedCollapseLength: CGFloat
        if #available(macOS 27.0, *) {
            boundedCollapseLength = Self.macOS27CollapseLength()
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

    // macOS 27 re-architected the menu bar and now DROPS a status item whose backing
    // window reaches half the width of the display (#360). The pre-27 length (twice the
    // widest screen) is over that limit on every Mac, so the separator was silently
    // ejected from the layout: it displaced nothing and hiding stopped working entirely.
    // Nothing in-process reports the ejection -- the item keeps reporting the length it
    // was asked for -- so the fix is to stay under the limit by construction.
    //
    // Measured on macOS 27.0 (26A428), 1728pt display, by reading foreign status items'
    // AXPosition while sweeping the length: 848pt hides them, 849pt hides nothing.
    // 848 + statusItemWindowChrome == 864 == 1728 / 2, i.e. the limit applies to the
    // item's WINDOW (length plus chrome), not to the length alone. The same arithmetic
    // fits the 3008pt-display report in PR #392 (honored at 1480pt, dropped at 1500pt).
    private static let statusItemWindowChrome: CGFloat = 16
    // Headroom under the measured cliff, so rounding or a chrome change on a later macOS
    // 27 build degrades the push a little instead of silently disabling hiding again.
    private static let macOS27Headroom: CGFloat = 24

    private static func macOS27CollapseLength() -> CGFloat {
        // One length is applied to the item on every display's copy of the menu bar and
        // the limit is per display, so the NARROWEST attached screen sets the cap --
        // the inverse of the pre-27 widest-screen rule. A length sized for a wide screen
        // would be over the limit on a narrow one and would hide nothing anywhere.
        let narrowestScreenWidth = NSScreen.screens.map { $0.frame.width }.min() ?? 1728
        let cap = narrowestScreenWidth / 2 - statusItemWindowChrome - macOS27Headroom
        // Never fall to or below the expanded length: isCollapsed is derived from
        // `length > btnHiddenLength`, so a degenerate cap would make the bar untoggleable.
        return max(120, cap)
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
            setLength(btnSeparate, to: btnHiddenLength)
        }
        if let alwaysHidden = btnAlwaysHidden {
            setLength(alwaysHidden, to: btnAlwaysHiddenLength)
        }
    }
    
    private func hideSeparators() {
        guard self.isBtnAlwaysHiddenValidPosition else {return}
        
        Preferences.areSeparatorsHidden = true
        
        if !self.isCollapsed {
            setLength(btnSeparate, to: btnHiddenLength)
        }
        if let alwaysHidden = btnAlwaysHidden {
            setLength(alwaysHidden, to: alwaysHiddenCollapseLength())
        }
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

        if needsHideMechanismVerification {
            // Drives the collapse itself: the canary has to take a live slot BEFORE the
            // separator grows, or there is nothing for the measurement to compare with.
            verifyHideMechanismThenCollapse()
        } else {
            setLength(btnSeparate, to: collapseLengthToApply())
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
        // Abandon an in-flight verification: its remaining attempts would re-inflate the
        // separator the user just opened. The next collapse starts over.
        abandonHideMechanismVerification()
        setLength(btnSeparate, to: btnHiddenLength)
        if let button = btnExpandCollapse.button {
            button.image = Assets.collapseImage
        }
        autoCollapseIfNeeded()
        
        if Preferences.useFullStatusBarOnExpandEnabled {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            
        }
    }
    
    // macOS 27 will not evict a seated neighbour to make room for an item that grows:
    // assigning the collapsed length in one jump leaves every icon exactly where it was,
    // which is the second half of #360 and is invisible to the length API (the item still
    // reports the length it was given). Measured on 27.0 (26A428): the same total applied
    // in small steps DOES carry the neighbours along -- foreign status items went from a
    // laid-out row to the parked position, and the icons left of the separator leave the
    // bar -- while a single jump moved them 0pt. Steps of 10 and 40pt both worked; 100pt
    // was already too coarse.
    //
    // Shrinking needs none of this: room becomes free and the host repacks on its own,
    // on every macOS. Pre-27 grows in one assignment as they always have.
    private static let lengthRampStep: CGFloat = 40
    private static let lengthRampInterval: TimeInterval = 0.016

    /// Sets a status item's length, ramping a macOS 27 GROWTH so the host carries the
    /// neighbouring icons along. Always cancels an in-flight ramp on the same item.
    private func setLength(_ item: NSStatusItem, to target: CGFloat) {
        let key = ObjectIdentifier(item)
        let generation = (lengthRampGenerations[key] ?? 0) &+ 1
        lengthRampGenerations[key] = generation

        guard #available(macOS 27.0, *), target > item.length else {
            item.length = target
            return
        }

        func advance() {
            // Abandon a ramp the user has already overtaken with another toggle.
            guard self.lengthRampGenerations[key] == generation else { return }
            let next = min(item.length + Self.lengthRampStep, target)
            item.length = next
            guard next < target else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.lengthRampInterval) {
                advance()
            }
        }
        advance()
    }

    /// Sets a length in one assignment, cancelling any in-flight ramp on the same item.
    private func setLengthImmediately(_ item: NSStatusItem, to target: CGFloat) {
        let key = ObjectIdentifier(item)
        lengthRampGenerations[key] = (lengthRampGenerations[key] ?? 0) &+ 1
        item.length = target
    }

    // Until a length has been proven, the formula's value is used as-is, so a first
    // collapse is never worse than it would be with no verification at all.
    private func collapseLengthToApply() -> CGFloat {
        return honoredCollapseLength ?? btnHiddenCollapseLength
    }

    // The always-hidden section inflates its own item the same way, so it meets the same
    // cliff. The separator's proven value stands in for it: measured on the same bar, and
    // a separate verification would need its own canary in the always-hidden zone.
    private func alwaysHiddenCollapseLength() -> CGFloat {
        guard let verified = honoredCollapseLength else {
            return btnAlwaysHiddenEnableExpandCollapseLength
        }
        return min(btnAlwaysHiddenEnableExpandCollapseLength, verified)
    }

    private var needsHideMechanismVerification: Bool {
        guard #available(macOS 27.0, *) else { return false }
        guard honoredCollapseLength == nil, !isVerifyingHideMechanism else { return false }
        // With the always-hidden section collapsed it is THAT separator parking the
        // leftmost items, so a canary would report success whatever this one does.
        // Fall back to the formula rather than prove the wrong thing.
        if Preferences.alwaysHiddenSectionEnabled, Preferences.areSeparatorsHidden {
            return false
        }
        return true
    }

    // Long enough for the canary to seat before the separator grows, and for the bar to
    // settle after it does. Measured on 27.0 (26A428): 0.35s left the canary unseated and
    // it travelled on an ejected 964pt request, reporting a hide that did not happen;
    // 1.0s and 2.0s both read that request correctly. It is spent once per display
    // configuration, on the first collapse.
    private static let canarySettleDelay: TimeInterval = 1.0
    // Each retry drops the request by a quarter. Starting at the formula value, a display
    // whose real cliff the formula overshoots is caught within one or two steps, while the
    // floor keeps the search from walking below the push any collapse needs.
    private static let canaryStepFactor: CGFloat = 0.75
    private static let canaryMaxAttempts = 6
    // How far the canary has to travel for the collapse to count as real. An ejected
    // separator leaves every neighbour where it was: measured on 27.0 (26A428), a 964pt
    // request (over this display's cliff) moved the hidden-zone icons 6pt, while an
    // honored 824pt request moved them ~470pt, to the region's left edge. A quarter of
    // the request, floored at an icon width, sits between those by a wide margin.
    //
    // Position alone cannot decide this: when the separator is clamped at the region's
    // left edge, a canary still holding a live slot sits within a few points of the
    // separator's own origin, exactly where a parked one does.
    private static func canaryRequiredDisplacement(for length: CGFloat) -> CGFloat {
        return max(32, length / 4)
    }
    // A canary that starts AT the point the separator clamps to had nowhere to travel:
    // the bar was full and parked it on arrival. Measured on 27.0 (26A428): a canary with
    // a real slot rested at 626pt while the separator clamped to 141pt, so a band of a
    // couple of icon widths around the clamp separates the two cases comfortably.
    private static let canaryClampBand: CGFloat = 64

    /// Collapses while proving, with one of our own items, that the collapse actually
    /// hides. Runs once per display configuration, and only on macOS 27+.
    private func verifyHideMechanismThenCollapse() {
        isVerifyingHideMechanism = true
        installCanary()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.canarySettleDelay) { [weak self] in
            guard let self = self, self.isVerifyingHideMechanism else { return }
            // A full bar parks a new item on arrival. Such a canary starts where a hidden
            // one ends up and can never demonstrate anything, so collapse the ordinary way
            // and leave the length unproven for a later collapse to retry.
            guard let resting = self.canaryLiveSlotOrigin() else {
                NSLog("HideMechanism: canary got no live slot, collapsing unverified")
                self.finishVerification(proving: nil)
                return
            }
            self.canaryRestingOrigin = resting
            self.attemptCollapse(length: self.btnHiddenCollapseLength, attempt: 1)
        }
    }

    private func attemptCollapse(length: CGFloat, attempt: Int) {
        setLength(btnSeparate, to: length)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.canarySettleDelay) { [weak self] in
            guard let self = self, self.isVerifyingHideMechanism else { return }
            if self.canaryWasDisplaced(by: length) {
                self.finishVerification(proving: length)
                return
            }
            // The separator has now clamped, so the clamp point is known and the canary's
            // starting position can be judged against it.
            if self.canaryStartedAtClamp() {
                NSLog("HideMechanism: canary started parked, collapsing unverified")
                self.finishVerification(proving: nil)
                return
            }
            let next = (length * Self.canaryStepFactor).rounded()
            guard attempt < Self.canaryMaxAttempts, next > self.btnHiddenLength else {
                NSLog("HideMechanism: no length hid the canary; hiding unavailable here")
                self.finishVerification(proving: nil)
                return
            }
            NSLog("HideMechanism: \(Int(length))pt did not hide, retrying at \(Int(next))pt")
            // Back to the expanded width first: on macOS 27 only a GROWING length evicts
            // a seated neighbour, so the next attempt has to grow into place.
            self.setLengthImmediately(self.btnSeparate, to: self.btnHiddenLength)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                guard self.isVerifyingHideMechanism else { return }
                self.attemptCollapse(length: next, attempt: attempt + 1)
            }
        }
    }

    private func finishVerification(proving verified: CGFloat?) {
        removeCanary()
        isVerifyingHideMechanism = false
        if let verified = verified {
            honoredCollapseLength = verified
            NSLog("HideMechanism: verified collapse length \(Int(verified))pt")
        }
        // Removing the canary frees its slot, so re-apply the length the collapse asked
        // for and let the ramp settle the bar into its final shape.
        setLength(btnSeparate, to: collapseLengthToApply())
        if Preferences.areSeparatorsHidden, let alwaysHidden = btnAlwaysHidden {
            setLength(alwaysHidden, to: alwaysHiddenCollapseLength())
        }
    }

    private func abandonHideMechanismVerification() {
        guard isVerifyingHideMechanism else { return }
        isVerifyingHideMechanism = false
        removeCanary()
    }

    /// A one-point, fully transparent status item registered LAST, so macOS places it
    /// leftmost -- inside the zone this collapse has to clear. It is on the bar for well
    /// under a second, once per display configuration, and never while idle.
    private func installCanary() {
        removeCanary()
        let item = NSStatusBar.system.statusItem(withLength: 1)
        item.autosaveName = "hiddenbar_probe"
        if let button = item.button {
            button.image = nil
            button.title = ""
            button.alphaValue = 0
            button.isEnabled = false
            button.appearsDisabled = true
        }
        item.isVisible = true
        canaryItem = item
    }

    private func removeCanary() {
        canaryRestingOrigin = nil
        guard let item = canaryItem else { return }
        NSStatusBar.system.removeStatusItem(item)
        canaryItem = nil
    }

    private func canaryOrigin() -> CGFloat? {
        return canaryItem?.button?.window?.frame.origin.x
    }

    /// The canary's origin, but only once it is placed on the hidden side of the
    /// separator. It does NOT land beside the separator -- macOS puts it leftmost in the
    /// icon row, which on a populated bar is hundreds of points away (626pt against a
    /// separator at 1141pt, measured) -- so this checks the side, not the distance.
    private func canaryLiveSlotOrigin() -> CGFloat? {
        guard let canaryX = canaryOrigin(),
              let separatorFrame = btnSeparate.button?.window?.frame else { return nil }
        let isOnHiddenSide = Constant.isUsingLTRLanguage
            ? canaryX < separatorFrame.minX
            : canaryX > separatorFrame.maxX
        return isOnHiddenSide ? canaryX : nil
    }

    /// Whether the canary began where a hidden item ends up. Such a canary can never
    /// demonstrate anything, and reading its stillness as failure would walk the collapse
    /// length down for nothing.
    private func canaryStartedAtClamp() -> Bool {
        guard let resting = canaryRestingOrigin,
              let separatorFrame = btnSeparate.button?.window?.frame else { return false }
        if Constant.isUsingLTRLanguage {
            return resting <= separatorFrame.minX + Self.canaryClampBand
        } else {
            return resting >= separatorFrame.maxX - Self.canaryClampBand
        }
    }

    /// Whether the collapse actually carried the canary out of its slot. This is the
    /// whole point of the canary: an ejected separator reports its full length and keeps
    /// its span, but moves no neighbour at all.
    private func canaryWasDisplaced(by length: CGFloat) -> Bool {
        guard let resting = canaryRestingOrigin, let now = canaryOrigin() else { return false }
        // The hidden zone is left of the separator in LTR and right of it in RTL, so the
        // direction a displaced item travels flips with the layout direction.
        let travelled = Constant.isUsingLTRLanguage ? resting - now : now - resting
        return travelled >= Self.canaryRequiredDisplacement(for: length)
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
                lengthRampGenerations.removeValue(forKey: ObjectIdentifier(existing))
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
                lengthRampGenerations.removeValue(forKey: ObjectIdentifier(existing))
                NSStatusBar.system.removeStatusItem(existing)
            }
            self.btnAlwaysHidden = nil
        }
    }
}
