//
//  NativeVisibilityEngine.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import AppKit

// macOS 27 hiding for the direct (non-App Store) build. Instead of inflating the
// separator, which macOS 27 ejects from the layout once it is too wide (#360),
// this reads which apps the user placed in each section and asks macOS to show
// only the allowed ones through the menu-bar visibility restriction behind
// assessment mode. macOS then hides the rest and reflows the bar itself, so the
// result does not depend on display width, the notch or the frontmost app's menus.
//
// The arrow is the boundary: apps left of it (LTR) are hidden, apps right of it
// stay visible. The regular separator is not needed and is taken out of the
// bar; even at zero width macOS keeps a gap for it. The always-hidden
// separator, when enabled, marks the third section; it shows while that section
// is shown so it can be ⌘-dragged, and is taken out of the bar while the section
// is hidden (collapsed, or expanded with "hide separators" on), where macOS has
// already removed everything it would separate. macOS puts it back where the
// user left it, which is what defines that section.
//
// Limits, all from what macOS 27 exposes:
// - Hiding is per app: an app with several icons hides or shows them together
//   (the most visible section wins).
// - macOS's own items (clock, Wi-Fi, Control Center...) are always kept visible:
//   Accessibility cannot tell them apart, so they cannot be mapped to sections.
//   SystemUIServer's legacy Menu Extras (Time Machine...) are the exception:
//   none was observed with a system item identifier, so they are sectioned
//   per bundle instead.
// - Sections are read only while nothing is hidden, because hidden items report
//   stale positions. They are re-read on the next collapse from an unrestricted
//   bar. An app that starts while something is hidden is not in the read, so it
//   gets the section it was last read in (remembered across launches), or the
//   visible one if it was never read, until that next read places it by where
//   macOS put its icon.
// - The restriction is assessment mode, which makes macOS ignore the clock, so
//   Notification Center cannot open from it (#410). A click on the clock while
//   collapsed expands the bar, presses the clock, and collapses again once the
//   panel closes (NotificationCenterSession in MenuBarClock).
// - Assessment mode also hides the capsule naming the app that uses the
//   microphone or camera (#432, #437; the dot in the screen corner stays). No
//   other restriction origin filters icons (measured on 27.0), so when a
//   microphone or camera turns on, the bar is expanded once to show it (a
//   Preferences option, on by default). Hiding is never blocked: apps such as
//   dictation tools keep the microphone open all day, so a collapse while
//   capture continues hides as usual, and only the next start expands again.
// - macOS matches the allow-list only to apps it knows by bundle id, which
//   (measured on 27.2) it does for an app in an Applications folder but not for
//   one run from elsewhere (Downloads, a build folder): it hides that app's
//   icons although they are allowed, Hidden Bar's own arrow included, leaving no
//   arrow to expand with. Outside an Applications folder nothing is hidden.
final class NativeVisibilityEngine: MenuBarEngine {
    // System item identifiers to keep visible. Unknown identifiers are ignored,
    // so the range covers items a given Mac does not have (0-63 checked on 27.0).
    static let systemItemsToKeep = Array(0..<64)

    private weak var items: MenuBarItemProvider?
    private let inventory: MenuBarInventoryProviding
    private let visibility: NativeVisibilityProviding
    private let clock: MenuBarClockProviding
    private let captureActivity: CaptureActivityMonitoring
    private let ownBundleIdentifier: String?
    private let itemFrame: (NSStatusItem) -> CGRect?
    private let displays: () -> [MenuBarDisplay]
    private let isLTR: () -> Bool
    private let runsFromApplicationsFolder: () -> Bool

    private let expandedLength: CGFloat = 20

    // .calibrating stands for "an activation is in flight".
    private(set) var state: MenuBarEngineState = .expanded
    private(set) var layout: MenuBarLayout?
    // The last read that listed every item, to fill in a read from an
    // overflowing menu bar. Kept across display changes: sections are per app.
    private var lastCompleteLayout: MenuBarLayout?

    private var assertion: NativeVisibilityAssertion?
    // What the held assertion allows besides Hidden Bar, and the generation it was
    // activated in, which stays current while nothing newer is in flight.
    private var assertionBundles: [String] = []
    private var assertionGeneration = 0
    // Bumped whenever a pending activation must no longer win (an expand, a newer
    // activation); a late success is then invalidated straight away.
    private var generation = 0
    private var lastUnavailableReason: String?
    // The capture state last seen, so only a start expands the bar. Capture
    // already running at launch is not a start.
    private var isCaptureActive: Bool
    private let expandsWhenCaptureStarts: () -> Bool

    private var alwaysHiddenEnabled = false
    private var alwaysHiddenSeparatorHidden = false

    // Where each app was last read, for apps that start while nothing can be read.
    private let sectionMemory: MenuBarSectionMemory
    // Apps that started since a read last listed them.
    private var launchedSinceRead: Set<String> = []
    private let workspaceNotifications: NotificationCenter?
    // Starts and quits of agent apps (no Dock icon), which NSWorkspace does
    // not post; most menu-bar apps are agents. Fed only with pinned sections on.
    private let agentLaunches: NotificationCenter?
    private var workspaceObservers: [(NotificationCenter, NSObjectProtocol)] = []

    // Pinned sections (beta): with it on, the table decides each app's section
    // and a read only edits it (PinnedSectionResolver). Off, sections come from
    // positions as in v1.11.2.
    private let pinnedSections: MenuBarSectionMemory
    private let pinsSections: () -> Bool

    // Items right of the arrow that the allow-list cannot keep visible: an item
    // whose owner has no bundle id, or a system extra no system item id covers
    // (Focus, Now Playing, User...) that macOS hid although Control Center's
    // bundle was allowed; those extras are remembered here. By default they are
    // hidden along with the rest, as before (Preferences lists them). Opting in
    // (`pausesHidingForUnkeepableItems`) keeps the whole bar shown instead.
    private var unkeepableSystemItems: Set<String> = []
    private let pausesHidingForUnkeepableItems: () -> Bool
    // Hidden extras leave Accessibility only once the bar has reflowed.
    var scheduleVisibilityCheck: (@escaping () -> Void) -> Void = {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: $0)
    }

    init(items: MenuBarItemProvider,
         inventory: MenuBarInventoryProviding = AccessibilityMenuBarInventory(),
         visibility: NativeVisibilityProviding = NativeVisibilityBridge(),
         clock: MenuBarClockProviding = SystemMenuBarClock(),
         captureActivity: CaptureActivityMonitoring = NoCaptureActivity(),
         ownBundleIdentifier: String? = Bundle.main.bundleIdentifier,
         itemFrame: @escaping (NSStatusItem) -> CGRect? = { $0.button?.window?.frame },
         displays: @escaping () -> [MenuBarDisplay] = MenuBarDisplay.current,
         isLTR: @escaping () -> Bool = { Constant.isUsingLTRLanguage },
         runsFromApplicationsFolder: @escaping () -> Bool = { true },
         pausesHidingForUnkeepableItems: @escaping () -> Bool = { false },
         expandsWhenCaptureStarts: @escaping () -> Bool = { true },
         sectionMemory: MenuBarSectionMemory = InMemorySectionMemory(),
         workspaceNotifications: NotificationCenter? = nil,
         pinnedSections: MenuBarSectionMemory = InMemorySectionMemory(),
         pinsSections: @escaping () -> Bool = { false },
         agentLaunches: NotificationCenter? = nil) {
        self.items = items
        self.agentLaunches = agentLaunches
        self.pinnedSections = pinnedSections
        self.pinsSections = pinsSections
        self.pausesHidingForUnkeepableItems = pausesHidingForUnkeepableItems
        self.inventory = inventory
        self.visibility = visibility
        self.clock = clock
        self.captureActivity = captureActivity
        isCaptureActive = captureActivity.isActive
        self.expandsWhenCaptureStarts = expandsWhenCaptureStarts
        self.ownBundleIdentifier = ownBundleIdentifier
        self.itemFrame = itemFrame
        self.displays = displays
        self.isLTR = isLTR
        self.runsFromApplicationsFolder = runsFromApplicationsFolder
        self.sectionMemory = sectionMemory
        self.workspaceNotifications = workspaceNotifications
        items.separatorItem.isVisible = false
        observeLaunches()
        captureActivity.onChange = { [weak self] in
            self?.captureActivityDidChange()
        }
    }

    deinit {
        workspaceObservers.forEach { center, observer in center.removeObserver(observer) }
    }

    func collapse(completion: @escaping (CollapseResult) -> Void) {
        switch state {
        case .collapsed:
            return completion(.collapsed)
        case .calibrating:
            // The activation in flight answers the request that started it.
            return
        case .expanded, .unavailable:
            break
        }
        if !hidesAlwaysHiddenSection {
            setSeparatorsVisible(true)
        }

        guard visibility.isAvailable else {
            logUnavailableOnce("the native menu-bar visibility API is not available in this build or on this macOS")
            state = .unavailable
            return completion(.unavailable)
        }
        guard runsFromApplicationsFolder() else {
            logUnavailableOnce("macOS 27 would also hide Hidden Bar's own arrow: it hides only apps it knows by bundle id, and Hidden Bar runs from outside an Applications folder (\(Bundle.main.bundlePath))")
            state = .unavailable
            return completion(.unavailable)
        }
        guard inventory.isAuthorized else {
            // Without Accessibility the sections cannot be read, and guessing would
            // hide icons the user kept visible. Not latched: it works as soon as
            // the permission is granted.
            inventory.requestAuthorization()
            logUnavailableOnce("Accessibility permission is needed to read the menu-bar sections")
            return completion(.unavailable)
        }
        state = .calibrating
        withLayout { [weak self] layout in
            guard let self = self else { return }
            guard let layout = layout else {
                self.logUnavailableOnce("the arrow's position cannot be read yet")
                self.state = .expanded
                return completion(.unavailable)
            }
            if self.pausesHidingForUnkeepableItems(),
               let reason = layout.reasonToKeepBarWhole(unkeepableSystemItems: self.unkeepableSystemItems) {
                self.logUnavailableOnce(reason)
                self.state = .expanded
                return completion(.unavailable)
            }
            self.activate(allowing: layout.bundles(in: [.visible])) { [weak self] succeeded in
                guard let self = self else { return }
                guard succeeded else {
                    self.state = .expanded
                    return completion(.unavailable)
                }
                self.checkStillShown(layout.unprovenVisibleSystemItems) { [weak self] shown in
                    guard let self = self else { return }
                    self.state = shown ? .collapsed : .expanded
                    if shown {
                        self.setSeparatorsVisible(false)
                    }
                    completion(shown ? .collapsed : .unavailable)
                    if shown {
                        self.allowLaunchedAppsIfIdle()
                    }
                }
            }
        }
    }

    func expand() {
        state = .expanded
        applyExpandedPresentation()
    }

    func updateAlwaysHiddenSection(enabled: Bool, separatorHidden: Bool) {
        alwaysHiddenEnabled = enabled
        alwaysHiddenSeparatorHidden = separatorHidden
        switch state {
        case .collapsed:
            // A separator created while collapsed arrives visible.
            setSeparatorsVisible(false)
        case .expanded:
            applyExpandedPresentation()
        case .calibrating, .unavailable:
            setSeparatorsVisible(true)
        }
    }

    // With pinned sections an app can be always hidden without the separator
    // (Preferences sets it), so a pinned always-hidden app counts too.
    private var hidesAlwaysHiddenSection: Bool {
        let hasSection = alwaysHiddenEnabled
            || (pinsSections() && pinnedSections.sections.values.contains(.alwaysHidden))
        return hasSection && alwaysHiddenSeparatorHidden
    }

    // Pinned sections hide the always-hidden section again at every collapse,
    // so an expand never shows it unless Option-click revealed it since (#224).
    func separatorsHiddenForCollapse(current: Bool) -> Bool {
        return pinsSections() ? true : current
    }

    // Where macOS 27 knows an app by its bundle id: /Applications (and folders
    // in it, such as Setapp's). Not ~/Applications: run from there, the arrow
    // still disappears on collapse. Symlinks are resolved first.
    static func isInApplicationsFolder(_ bundleURL: URL,
                                       applicationFolders: [URL] = FileManager.default.urls(for: .applicationDirectory,
                                                                                            in: .localDomainMask)) -> Bool {
        let path = bundleURL.resolvingSymlinksInPath().standardizedFileURL.path
        return applicationFolders.contains { folder in
            path.hasPrefix(folder.resolvingSymlinksInPath().standardizedFileURL.path + "/")
        }
    }

    // Sections are per app and come from the arrangement, which a display change
    // does not alter, so a held restriction stays right and the bar stays
    // collapsed. Only an unused cache is dropped; the next read from an
    // unrestricted bar measures against the displays connected then.
    func invalidateLayout() {
        if assertion == nil {
            layout = nil
        }
    }

    // Expanded shows the hidden section; the always-hidden section stays hidden
    // while "hide separators" is on, otherwise everything is revealed by dropping
    // the restriction altogether. Its separator goes and comes back with it, only
    // once the icons are hidden, so it never disappears on its own.
    private func applyExpandedPresentation() {
        guard hidesAlwaysHiddenSection, visibility.isAvailable, runsFromApplicationsFolder(), inventory.isAuthorized else {
            return revealAll()
        }
        withLayout { [weak self] layout in
            guard let self = self else { return }
            guard let layout = layout else {
                return self.revealAll()
            }
            self.activate(allowing: layout.bundles(in: [.visible, .hidden])) { [weak self] succeeded in
                self?.setSeparatorsVisible(!succeeded)
                if succeeded {
                    self?.allowLaunchedAppsIfIdle()
                }
            }
        }
    }

    private func revealAll() {
        releaseAssertion()
        setSeparatorsVisible(true)
    }

    // The sections as the user arranged them. Read fresh only from an
    // unrestricted bar; while a restriction is active the cached ones stand in.
    // Superseded by any later expand or activation, like an activation is.
    private func withLayout(_ body: @escaping (MenuBarLayout?) -> Void) {
        if assertion != nil {
            return body(layout)
        }
        guard let arrow = items?.toggleItem,
              var boundary = itemFrame(arrow) else { return body(nil) }
        var alwaysHiddenFrame = alwaysHiddenEnabled ? items?.alwaysHiddenItem.flatMap(itemFrame) : nil
        #if DEBUG
        if let x = Self.debugBoundaryX {
            boundary.origin.x = x - boundary.width / 2
        }
        if alwaysHiddenEnabled, let x = Self.debugAlwaysHiddenX {
            alwaysHiddenFrame = CGRect(x: x, y: boundary.minY, width: 1, height: boundary.height)
        }
        #endif
        let isLTR = self.isLTR()
        generation += 1
        let generation = self.generation
        inventory.snapshot { [weak self] inventory in
            guard let self = self, generation == self.generation else { return }
            // Read after the snapshot, which takes about a second: a display
            // attached meanwhile is then known. An arrow on no display has no
            // edge to measure the sections from.
            let displays = self.displays()
            guard displays.isEmpty || MenuBarDisplay.containing(appKitFrame: boundary, in: displays) != nil else {
                NSLog("NativeVisibility: the arrow at \(NSStringFromRect(boundary)) is on no display \(displays.map { NSStringFromRect($0.appKitFrame) })")
                return body(nil)
            }
            var layout = MenuBarLayoutResolver.resolve(inventory: inventory,
                                                       separatorFrame: boundary,
                                                       alwaysHiddenSeparatorFrame: alwaysHiddenFrame,
                                                       displays: displays,
                                                       isLTR: isLTR,
                                                       excludingBundle: self.ownBundleIdentifier)
            if layout.isIncomplete {
                // Apps macOS left out would be hidden although they may be
                // right of the arrow; with no complete read to take them from,
                // nothing may be hidden.
                guard let complete = self.lastCompleteLayout else {
                    NSLog("NativeVisibility: the active menu bar overflows and no complete read exists yet; leaving the bar whole")
                    return body(nil)
                }
                layout = layout.fillingIn(from: complete)
                NSLog("NativeVisibility: the active menu bar overflows; apps it does not list keep their last known section")
            } else {
                self.lastCompleteLayout = layout
            }
            if self.pinsSections() {
                var observed = self.sectionMemory.sections
                var table = self.pinnedSections.sections
                layout.sections = PinnedSectionResolver.resolve(read: layout.sections,
                                                                launchedSinceRead: self.launchedSinceRead,
                                                                observed: &observed, table: &table)
                self.sectionMemory.sections = observed
                self.pinnedSections.sections = table
            } else {
                self.sectionMemory.sections.merge(layout.sections) { _, read in read }
            }
            self.launchedSinceRead.subtract(layout.sections.keys)
            for bundle in self.launchedSinceRead {
                // Started, but its icon was not listed yet.
                layout.sections[bundle] = self.rememberedSection(of: bundle)
            }
            NSLog("NativeVisibility: arrow at x=\(boundary.midX); visible \(layout.bundles(in: [.visible])), hidden \(layout.bundles(in: [.hidden])), always hidden \(layout.bundles(in: [.alwaysHidden]))")
            if !layout.unnameableVisibleItems.isEmpty || !layout.unprovenVisibleSystemItems.isEmpty {
                NSLog("NativeVisibility: visible without a bundle id \(layout.unnameableVisibleItems); visible system extras to check \(layout.unprovenVisibleSystemItems)")
            }
            self.layout = layout
            body(layout)
        }
    }

    // Activates the new restriction before dropping the old one, so switching
    // between collapsed and expanded never flashes the whole bar visible.
    private func activate(allowing bundles: [String], completion: @escaping (Bool) -> Void) {
        generation += 1
        let generation = self.generation
        let allowed = (ownBundleIdentifier.map { [$0] } ?? []) + bundles
        visibility.activate(allowedSystemItems: Self.systemItemsToKeep,
                            allowedBundleIdentifiers: allowed) { [weak self] result in
            guard let self = self, generation == self.generation else {
                if case .success(let stale) = result { stale.invalidate() }
                return
            }
            switch result {
            case .success(let newAssertion):
                let old = self.assertion
                self.assertion = newAssertion
                self.assertionBundles = bundles
                self.assertionGeneration = generation
                old?.invalidate()
                self.watchClock()
                completion(true)
            case .failure(let error):
                // Fail open: never leave icons hidden after an error.
                NSLog("NativeVisibility: activation failed: \(error.localizedDescription)")
                self.releaseAssertion()
                completion(false)
            }
        }
    }

    // The always-hidden separator is taken out of the bar while its section is
    // hidden; a zero-width item would still be there and clickable.
    private func setSeparatorsVisible(_ visible: Bool) {
        items?.separatorItem.isVisible = false
        let shown = visible && alwaysHiddenEnabled
        items?.alwaysHiddenItem?.length = shown ? expandedLength : 0
        items?.alwaysHiddenItem?.isVisible = shown
    }

    // Any arrangement works: whatever sits left of the arrow is the hidden section.
    var isArrangementValid: Bool {
        return true
    }

    var isAlwaysHiddenSeparatorPlaced: Bool {
        return MenuBarOrder.isItem(items?.alwaysHiddenItem, onHiddenSideOf: items?.toggleItem)
    }

    private func releaseAssertion() {
        generation += 1
        assertion?.invalidate()
        assertion = nil
        watchClock()
    }

    // A start expands the bar the way the arrow does (state, arrow, auto-hide),
    // without bringing Hidden Bar forward, and an expanded bar that still hides the always-hidden section shows it
    // too. A collapse in flight is left to land. Nothing else follows capture.
    private func captureActivityDidChange() {
        let isActive = captureActivity.isActive
        guard isActive != isCaptureActive else { return }
        isCaptureActive = isActive
        guard isActive, expandsWhenCaptureStarts() else { return }
        NSLog("NativeVisibility: a microphone or camera turned on; showing the whole menu bar once")
        if state == .collapsed {
            if let expandBar = expandBarForCapture { expandBar() } else { expand() }
        }
        if state == .expanded {
            revealAll()
        }
    }

    // Any held restriction, collapsed or expanded with the always-hidden section
    // hidden, stops the clock from opening Notification Center.
    private func watchClock() {
        clock.onClick = assertion == nil ? nil : { [weak self] location in
            self?.clockClicked(at: location)
        }
    }

    // Set by the controller to its own expand and collapse, so a clock click
    // changes the bar exactly as a click on the arrow does (state, arrow,
    // auto-collapse, activation policy). Without them the engine's own are used.
    var expandBar: (() -> Void)?
    var collapseBar: (() -> Void)?
    // The controller's expand for a microphone or camera turning on, which must
    // not take focus from the app that turned it on.
    var expandBarForCapture: (() -> Void)?
    var clockNow: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    var scheduleClockStep: (TimeInterval, @escaping () -> Void) -> Void = {
        DispatchQueue.main.asyncAfter(deadline: .now() + $0, execute: $1)
    }

    private lazy var notificationCenter = NotificationCenterSession(
        now: { [weak self] in self?.clockNow() ?? 0 },
        after: { [weak self] in self?.scheduleClockStep($0, $1) },
        panelIsOpen: { [weak self] in self?.clock.isNotificationCenterOpen ?? false },
        press: { [weak self] in self?.pressClock(at: $0, mode: $1, finished: $2) ?? true },
        expand: { [weak self] in
            guard let self = self else { return }
            if let expandBar = self.expandBar { expandBar() } else { self.expand() }
        },
        collapse: { [weak self] in
            guard let self = self else { return }
            if let collapseBar = self.collapseBar { collapseBar() } else { self.collapse { _ in } }
        })

    // Auto-collapse waits while Notification Center, opened from the clock, is open.
    var defersAutoCollapse: Bool {
        return notificationCenter.isActive
    }

    // The last read, plus apps an overflowing menu bar left out of it.
    var menuBarItemOwners: Set<String> {
        let read = layout?.sections.keys.map { $0 } ?? []
        let complete = lastCompleteLayout?.sections.keys.map { $0 } ?? []
        return Set(read + complete)
    }

    func userChangedBar() {
        notificationCenter.userChangedBar()
    }

    private func clockClicked(at location: CGPoint) {
        // Not while an activation, a section read or a collapse's visibility
        // check is in flight: expanding or lifting now would cancel it, and a
        // cancelled collapse never reports back, leaving the bar stuck calibrating.
        guard assertion != nil, generation == assertionGeneration, state != .calibrating else { return }
        NSLog("NativeVisibility: a click on the clock while \(state == .collapsed ? "collapsed; expanding" : "expanded")")
        notificationCenter.clockClicked(at: location, barCollapsed: state == .collapsed)
    }

    // The longest the restriction may stay lifted for one press, whatever the
    // press does: the lift, the AX lookup and the panel timeout fit well inside.
    static let clockLiftHardCap: TimeInterval = 0.6
    var scheduleRestoreWatchdog: (TimeInterval, @escaping () -> Void) -> Void = {
        DispatchQueue.main.asyncAfter(deadline: .now() + $0, execute: $1)
    }

    // Replays one click on the clock. Unrestricted (the bar was expanded), the
    // clock works and is simply pressed. A restriction still held, which only
    // the expanded bar with the always-hidden section hidden keeps, is lifted
    // just long enough for the press to land and then put back; the
    // always-hidden icons can show for that moment. False while an activation
    // is in flight (the one an expand starts, say): lifting would cancel it.
    private func pressClock(at location: CGPoint, mode: ClockPressMode,
                            finished: @escaping (ClockPressOutcome) -> Void) -> Bool {
        guard assertion != nil else {
            clock.press(at: location, mode: mode, restore: {}, finished: finished)
            return true
        }
        guard generation == assertionGeneration, state != .calibrating else { return false }
        NSLog("NativeVisibility: lifting the restriction for a click on the clock")
        #if DEBUG
        ClockFlashTimeline.mark(mode == .restoreAfterPress ? "liftRequested" : "retryLiftRequested")
        #endif
        let bundles = assertionBundles
        releaseAssertion()
        let generation = self.generation
        var restored = false
        let restore = { [weak self] in
            guard !restored else { return }
            restored = true
            // An expand or collapse meanwhile already applied what the user wants.
            guard let self = self, generation == self.generation else { return }
            #if DEBUG
            ClockFlashTimeline.mark("reapplyRequested")
            #endif
            self.activate(allowing: bundles) { [weak self] succeeded in
                #if DEBUG
                ClockFlashTimeline.mark("reapplyEffective")
                #endif
                guard let self = self, !succeeded else { return }
                self.state = .expanded
                self.setSeparatorsVisible(true)
            }
        }
        // Never leave the bar unrestricted, even if the press never reports back.
        scheduleRestoreWatchdog(Self.clockLiftHardCap) {
            #if DEBUG
            if !restored { ClockFlashTimeline.mark("watchdog") }
            #endif
            restore()
        }
        clock.press(at: location, mode: mode, restore: restore, finished: finished)
        return true
    }

    private func observeLaunches() {
        func bundle(_ note: Notification) -> String? {
            return (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
        }
        for center in [workspaceNotifications, agentLaunches].compactMap({ $0 }) {
            workspaceObservers += [
                (center, center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
                    bundle(note).map { self?.applicationLaunched($0) }
                }),
                (center, center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                    bundle(note).map { self?.applicationTerminated($0) }
                })
            ]
        }
    }

    // A held restriction allows only the apps it was given, so an app that
    // starts meanwhile would be hidden wherever macOS puts its icon (new icons,
    // login items that start after Hidden Bar, an app quit at the last read).
    // It gets the section it was last read in, or visible if it never was.
    // An app the last read listed keeps that section.
    func applicationLaunched(_ bundle: String) {
        guard bundle != ownBundleIdentifier,
              !MenuBarLayoutResolver.systemItemOwners.contains(bundle) else { return }
        launchedSinceRead.insert(bundle)
        guard var layout = layout, layout.sections[bundle] == nil else { return }
        layout.sections[bundle] = rememberedSection(of: bundle)
        self.layout = layout
        allowLaunchedAppsIfIdle()
    }

    // The section of an app no read lists yet: its pinned one with the beta on,
    // else where it was last read; visible when neither knows it.
    private func rememberedSection(of bundle: String) -> MenuBarSection {
        if pinsSections() {
            return pinnedSections.sections[bundle] ?? PinnedSectionResolver.newAppSection
        }
        return sectionMemory.sections[bundle] ?? .visible
    }

    // Preferences changed the pinned sections: apply them to the held
    // restriction at once. A collapse or expand in flight applies them when it
    // lands. Apps no read listed yet keep the section they were given.
    func pinnedSectionsDidChange() {
        guard pinsSections(), var layout = layout else { return }
        let table = pinnedSections.sections
        for bundle in layout.sections.keys {
            if let pinned = table[bundle] { layout.sections[bundle] = pinned }
        }
        self.layout = layout
        NSLog("NativeVisibility: pinned sections changed; visible \(layout.bundles(in: [.visible])), hidden \(layout.bundles(in: [.hidden])), always hidden \(layout.bundles(in: [.alwaysHidden]))")
        switch state {
        case .collapsed:
            allowLaunchedAppsIfIdle()
        case .expanded:
            applyExpandedPresentation()
        case .calibrating, .unavailable:
            break
        }
    }

    func applicationTerminated(_ bundle: String) {
        launchedSinceRead.remove(bundle)
    }

    // Swaps the held restriction for one that also allows apps placed since it
    // was activated. Not while anything is in flight; the collapse or expand
    // that lands calls this again.
    private func allowLaunchedAppsIfIdle() {
        guard assertion != nil, generation == assertionGeneration, state != .calibrating,
              let layout = layout else { return }
        let shownSections: Set<MenuBarSection> = state == .collapsed ? [.visible] : [.visible, .hidden]
        let wanted = layout.bundles(in: shownSections)
        guard wanted != assertionBundles else { return }
        NSLog("NativeVisibility: allowing apps that started while hiding: \(Set(wanted).subtracting(assertionBundles).sorted())")
        activate(allowing: wanted) { [weak self] succeeded in
            guard let self = self, !succeeded else { return }
            self.state = .expanded
            self.setSeparatorsVisible(true)
        }
    }

    // Logged when the reason changes, so a retried collapse does not spam.
    private func logUnavailableOnce(_ reason: String) {
        guard reason != lastUnavailableReason else { return }
        lastUnavailableReason = reason
        NSLog("NativeVisibility: hiding unavailable: \(reason)")
    }

    // Checks whether macOS hid a system extra the allow-list could only try to
    // keep, and remembers the ones it did. By default the bar stays collapsed
    // and the check only feeds the Preferences note. With the opt-in, the
    // restriction is dropped and later collapses keep the bar whole while such an
    // extra is right of the arrow, instead of flashing it hidden.
    private func checkStillShown(_ expected: [String], completion: @escaping (Bool) -> Void) {
        let unchecked = expected.filter { !unkeepableSystemItems.contains($0) }
        guard !unchecked.isEmpty else { return completion(true) }
        let pauses = pausesHidingForUnkeepableItems()
        if !pauses {
            completion(true)
        }
        let generation = self.generation
        scheduleVisibilityCheck { [weak self] in
            guard let self = self, generation == self.generation else { return }
            self.inventory.snapshot { [weak self] inventory in
                guard let self = self, generation == self.generation else { return }
                let missing = MenuBarLayoutResolver.missingSystemItems(unchecked, in: inventory)
                if !missing.isEmpty {
                    self.rememberUnkeepable(missing)
                }
                guard pauses else {
                    if !missing.isEmpty {
                        NSLog("NativeVisibility: macOS also hides \(missing) although they sit right of the arrow")
                    }
                    return
                }
                guard missing.isEmpty else {
                    NSLog("NativeVisibility: macOS hid \(missing) although they sit right of the arrow; keeping the bar whole while they are there")
                    self.releaseAssertion()
                    return completion(false)
                }
                completion(true)
            }
        }
    }

    // What Preferences shows as "macOS 27 also hides".
    static private(set) var knownUnkeepableSystemItems: [String] = []

    private func rememberUnkeepable(_ identifiers: [String]) {
        unkeepableSystemItems.formUnion(identifiers)
        Self.knownUnkeepableSystemItems = unkeepableSystemItems.sorted()
        NotificationCenter.default.post(name: .unkeepableSystemItemsChanged, object: nil)
    }

    // "com.apple.menuextra.now-playing" -> "Now Playing".
    static func displayName(ofSystemItem identifier: String) -> String {
        let known = ["focusmode": "Focus", "now-playing": "Now Playing", "user": "User",
                     "siri": "Siri", "stagemanager": "Stage Manager", "timemachine": "Time Machine"]
        let name = identifier.components(separatedBy: ".").last ?? identifier
        return known[name] ?? name.replacingOccurrences(of: "-", with: " ").capitalized
    }
}

// NSWorkspace posts didLaunch/didTerminateApplication only for apps with a
// Dock icon, and most menu-bar apps are agents (LSUIElement) it skips. Watching
// runningApplications sees every app; this posts the agents' starts and quits
// as those same notifications. Apps with a Dock icon are left to NSWorkspace,
// so no start is reported twice or out of order.
final class AgentLaunchNotifications: NotificationCenter, @unchecked Sendable {
    private var observation: NSKeyValueObservation?

    init(workspace: NSWorkspace = .shared, isActive: @escaping () -> Bool) {
        super.init()
        observation = workspace.observe(\.runningApplications, options: [.old, .new]) { [weak self] _, change in
            guard let self = self, isActive() else { return }
            let notes = Self.notifications(kind: change.kind, inserted: change.newValue ?? [], removed: change.oldValue ?? [],
                                           isAgent: { $0.activationPolicy != .regular })
            DispatchQueue.main.async {
                for (name, app) in notes {
                    self.post(name: name, object: nil, userInfo: [NSWorkspace.applicationUserInfoKey: app])
                }
            }
        }
    }

    // Reported with or without pinned sections: without them, the launch
    // handling for apps that start while collapsed (#446) misses every agent.
    static func isActive(pinnedSectionsEnabled: Bool) -> Bool {
        return true
    }

    static func notifications<App>(kind: NSKeyValueChange, inserted: [App], removed: [App],
                                   isAgent: (App) -> Bool) -> [(Notification.Name, App)] {
        switch kind {
        case .insertion:
            return inserted.filter(isAgent).map { (NSWorkspace.didLaunchApplicationNotification, $0) }
        case .removal:
            return removed.filter(isAgent).map { (NSWorkspace.didTerminateApplicationNotification, $0) }
        default:
            return []
        }
    }
}

extension Notification.Name {
    // Posted on the main queue when NativeVisibilityEngine.knownUnkeepableSystemItems changes.
    static let unkeepableSystemItemsChanged = Notification.Name("unkeepableSystemItemsChanged")
}

#if DEBUG
// Test hooks (Debug builds only); see StatusBarController's debug extension.
extension NativeVisibilityEngine {
    // Section boundaries to use instead of the items' real positions, so a
    // harness can place sections without ⌘-dragging anything.
    static var debugBoundaryX: CGFloat?
    static var debugAlwaysHiddenX: CGFloat?
    static var debugChecksInstallLocation = false

    var debugState: [String: Any] {
        var sections: [String: String] = [:]
        layout?.sections.forEach { sections[$0.key] = String(describing: $0.value) }
        return [
            "assertionHeld": assertion != nil,
            "allowedBundles": assertion == nil ? [] : assertionBundles,
            "sections": sections,
            "clockWatched": clock.onClick != nil,
            "captureActive": captureActivity.isActive,
            "unprovenVisibleSystemItems": layout?.unprovenVisibleSystemItems ?? [],
            "unnameableVisibleItems": layout?.unnameableVisibleItems ?? [],
            "unkeepableSystemItems": unkeepableSystemItems.sorted(),
            "pausesHidingForUnkeepableItems": pausesHidingForUnkeepableItems(),
            "lastUnavailableReason": lastUnavailableReason ?? NSNull(),
            "displays": displays().map { NSStringFromRect($0.appKitFrame) },
            "debugBoundaryX": Self.debugBoundaryX.map { Double($0) } ?? NSNull(),
            "debugAlwaysHiddenX": Self.debugAlwaysHiddenX.map { Double($0) } ?? NSNull(),
            "clockTimeline": ClockFlashTimeline.snapshot,
            "notificationCenterSession": ["active": notificationCenter.isActive,
                                          "expandedBar": notificationCenter.expandedBar],
            "pinsSections": pinsSections(),
            "pinnedSections": pinnedSections.sections.mapValues { String(describing: $0) },
            "observedSections": sectionMemory.sections.mapValues { String(describing: $0) },
            "launchedSinceRead": launchedSinceRead.sorted()
        ]
    }

    // Runs the clock-click handler the global mouse monitor would run, with the
    // replayed press posted to MenuBarAgent's process instead of the HID stream.
    func debugClockClicked(at location: CGPoint, postingTo pid: pid_t, pressingWithAX: Bool = false) {
        SystemMenuBarClock.debugPostToPid = pid
        SystemMenuBarClock.debugPressWithAX = pressingWithAX
        clock.onClick?(location)
    }
}
#endif
