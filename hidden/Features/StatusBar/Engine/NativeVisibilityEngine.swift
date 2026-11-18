//
//  NativeVisibilityEngine.swift
//  Hidden Bar
//
//  Copyright © 2026 Console Labs. All rights reserved.
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
// - An app that turns Accessibility off (Little Snitch) cannot be placed: its
//   icons count as visible wherever they sit, like an app that never answers.
//   With pinned sections on, Settings › Icons can still hide it.
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
// - Presentation mode (F4) is a second allow-list held through the same
//   restriction: every app hidden, or the hidden section shown minus the
//   sensitive apps. Every change to what is held goes through `hold(whenBar:)`
//   and `reconcileHold()`, so no event (an app launch, a clock click, a capture
//   change) can swap the strict list back to the normal one. The restriction
//   hides the capsule naming the app that records, so presentation follows the
//   main bar's rule: it lifts once when a microphone or camera turns on, if
//   that switch is on, and the user may hide again at once. A capture already
//   running when the mode starts does not lift it, as it would not expand a
//   collapsed main bar. It lifts when the app quits (PresentationState).
// - macOS matches the allow-list only to apps it knows by bundle id, which
//   (measured on 27.2) it does for an app in an Applications folder but not for
//   one run from elsewhere (Downloads, a build folder): it hides that app's
//   icons although they are allowed, Hidden Bar's own arrow included, leaving no
//   arrow to expand with. Outside an Applications folder nothing is hidden.
//   Another app run from elsewhere (iStat Menus 7 from Application Support,
//   #521) is hidden the same way although it is allowed; Preferences lists it
//   with the system items macOS will not keep, and the opt-in keeps the bar
//   whole while one sits right of the arrow.
// Everything one held restriction allows besides Hidden Bar itself. Two holds are
// the same only when every part matches, so a swap between lists that name the
// same apps but different system items is not skipped.
struct NativeHold: Equatable {
    let systemItems: [Int]
    let bundles: [String]
}

final class NativeVisibilityEngine: MenuBarEngine {
    // System item identifiers to keep visible. Unknown identifiers are ignored,
    // so the range covers items a given Mac does not have (0-63 checked on 27.0).
    static let systemItemsToKeep = Array(0..<64)
    // Presentation mode keeps the clock and battery. Which of these ids are those
    // two has not been measured on a live bar, so the strict list keeps the same
    // ids; the apps, which are what a presentation must not show, are all hidden.
    static let presentationSystemItems = systemItemsToKeep

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
    // Told about every read taken from an unrestricted bar, with the raw
    // inventory it came from, and the sections that read listed (apps that only
    // started are not in it). The app catalog listens here.
    var onUnrestrictedRead: ((MenuBarLayout, [MenuBarInventoryItem]) -> Void)?
    // The last read that listed every item, to fill in a read from an
    // overflowing menu bar. Kept across display changes: sections are per app.
    private var lastCompleteLayout: MenuBarLayout?

    private var assertion: NativeVisibilityAssertion?
    // What the held assertion allows besides Hidden Bar, and the generation it was
    // activated in, which stays current while nothing newer is in flight.
    private var assertionBundles: [String] = []
    private var assertionSystemItems: [Int] = NativeVisibilityEngine.systemItemsToKeep
    // The hold requested last and not landed yet, so a newer wish is compared
    // with it and not only with what is held.
    private var inFlightHold: NativeHold?
    private var assertionGeneration = 0
    // Bumped whenever a pending activation must no longer win (an expand, a newer
    // activation); a late success is then invalidated straight away.
    private var generation = 0
    private var lastUnavailableReason: String?
    // The capture state last seen, so only a start expands the bar. Capture
    // already running at launch is not a start.
    private var isCaptureActive: Bool
    private let expandsWhenCaptureStarts: () -> Bool
    private let sensitiveApps: () -> Set<String>
    private var presentation = PresentationState()
    private var seenPhase: PresentationPhase = .off
    private var terminationObserver: (NotificationCenter, NSObjectProtocol)?
    // Told on the main queue whenever the phase changes; the capsule follows it.
    var onPresentationChange: ((PresentationPhase) -> Void)?

    private var alwaysHiddenEnabled = false
    private var alwaysHiddenSeparatorHidden = false

    // The one app the palette lets show, with the apps the held restriction
    // allowed before that.
    private var temporaryAllow: (bundle: String, before: [String])?

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
    private let ignoredDrags: () -> Set<String>
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
         sensitiveApps: @escaping () -> Set<String> = { [] },
         terminationNotifications: NotificationCenter = .default,
         sectionMemory: MenuBarSectionMemory = InMemorySectionMemory(),
         workspaceNotifications: NotificationCenter? = nil,
         pinnedSections: MenuBarSectionMemory = InMemorySectionMemory(),
         pinsSections: @escaping () -> Bool = { false },
         ignoredDrags: @escaping () -> Set<String> = { [] },
         agentLaunches: NotificationCenter? = nil) {
        self.items = items
        self.ignoredDrags = ignoredDrags
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
        self.sensitiveApps = sensitiveApps
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
        // Quit lifts the restriction explicitly as well as by process exit.
        terminationObserver = (terminationNotifications, terminationNotifications.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { [weak self] _ in
                self?.releaseAssertion()
            })
    }

    deinit {
        terminationObserver.map { $0.0.removeObserver($0.1) }
        workspaceObservers.forEach { center, observer in center.removeObserver(observer) }
    }

    func collapse(completion report: @escaping (CollapseResult) -> Void) {
        // Presentation mode shows "could not hide" when a collapse that should
        // have hidden everything did not.
        let completion: (CollapseResult) -> Void = { [weak self] result in
            self?.collapseFinished(result)
            report(result)
        }
        switch state {
        case .collapsed:
            return completion(.collapsed)
        case .calibrating:
            // The activation in flight answers the request that started it.
            return
        case .expanded, .unavailable:
            break
        }
        // A collapse during the camera or microphone pause is the user choosing to
        // hide again (as on the main bar, where a collapse during capture hides as
        // usual): presentation mode resumes and the collapse holds the strict list.
        if presentation.isOn, currentPhase() == .paused {
            NSLog("NativeVisibility: a collapse while presentation mode is paused; hiding again")
            resumePresentationHiding(collapsing: false)
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
            // The strict presentation list names no app from a read, so it holds
            // without Accessibility.
            if holdsPresentationList {
                return holdPresentationListUnread(completion)
            }
            // Without Accessibility the sections cannot be read, and guessing would
            // hide icons the user kept visible. Not latched: it works as soon as
            // the permission is granted.
            inventory.requestAuthorization()
            logUnavailableOnce("Accessibility permission is needed to read the menu-bar sections")
            return completion(.unavailable)
        }
        state = .calibrating
        startCollapseTimeout(completion)
        withLayout { [weak self] layout in
            guard let self = self else { return }
            guard let layout = layout else {
                // The strict presentation list needs no layout.
                if self.holdsPresentationList {
                    return self.holdPresentationListUnread(completion)
                }
                self.logUnavailableOnce("the arrow's position cannot be read yet")
                self.state = .expanded
                return completion(.unavailable)
            }
            if !self.holdsPresentationList, self.pausesHidingForUnkeepableItems(),
               let reason = layout.reasonToKeepBarWhole(unkeepableSystemItems: self.unkeepableSystemItems) {
                self.logUnavailableOnce(reason)
                self.state = .expanded
                return completion(.unavailable)
            }
            guard let wanted = self.hold(whenBar: .collapsed, layout: layout) else {
                self.state = .expanded
                return completion(.unavailable)
            }
            self.activate(wanted) { [weak self] succeeded in
                guard let self = self else { return }
                guard succeeded else {
                    self.state = .expanded
                    return completion(.unavailable)
                }
                self.checkStillShown(self.holdsPresentationList ? [] : layout.unprovenVisibleSystemItems) { [weak self] shown in
                    guard let self = self else { return }
                    self.state = shown ? .collapsed : .expanded
                    if shown {
                        self.setSeparatorsVisible(false)
                    }
                    completion(shown ? .collapsed : .unavailable)
                    if shown {
                        self.settleHold()
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
    //
    // While presenting, the expanded bar keeps a restriction too: the hidden
    // section shows except the sensitive apps. A missing layout never falls back
    // to revealing then; the strict list needs none.
    private func applyExpandedPresentation() {
        let presenting = holdsPresentationList
        guard hidesAlwaysHiddenSection || presenting, visibility.isAvailable, runsFromApplicationsFolder() else {
            return revealAll()
        }
        guard inventory.isAuthorized else {
            guard presenting, let wanted = hold(whenBar: .expanded, layout: nil) else { return revealAll() }
            return activate(wanted) { [weak self] succeeded in
                self?.setSeparatorsVisible(!succeeded)
            }
        }
        withLayout { [weak self] layout in
            guard let self = self else { return }
            guard let wanted = self.hold(whenBar: .expanded, layout: layout) else {
                return self.revealAll()
            }
            self.activate(wanted) { [weak self] succeeded in
                self?.setSeparatorsVisible(!succeeded)
                if succeeded {
                    self?.settleHold()
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
                                                                ignoringDrags: self.ignoredDrags(),
                                                                observed: &observed, table: &table)
                self.sectionMemory.sections = observed
                self.pinnedSections.sections = table
            } else {
                self.sectionMemory.sections.merge(layout.sections) { _, read in read }
            }
            self.launchedSinceRead.subtract(layout.sections.keys)
            // What the read listed, before apps that only started are filled in:
            // those may have no menu-bar icon at all.
            self.onUnrestrictedRead?(layout, inventory)
            for bundle in self.launchedSinceRead {
                // Started, but its icon was not listed yet.
                layout.sections[bundle] = self.rememberedSection(of: bundle)
            }
            NSLog("NativeVisibility: arrow at x=\(boundary.midX); visible \(layout.bundles(in: [.visible])), hidden \(layout.bundles(in: [.hidden])), always hidden \(layout.bundles(in: [.alwaysHidden]))")
            if !layout.unnameableVisibleItems.isEmpty || !layout.unprovenVisibleSystemItems.isEmpty {
                NSLog("NativeVisibility: visible without a bundle id \(layout.unnameableVisibleItems); visible system extras to check \(layout.unprovenVisibleSystemItems)")
            }
            let unkeepableApps = layout.unkeepableVisibleApps
            if !unkeepableApps.isEmpty, !Set(unkeepableApps).isSubset(of: Self.knownUnkeepableApps) {
                NSLog("NativeVisibility: macOS hides \(unkeepableApps) although they are allowed: they run from outside an Applications folder")
                Self.knownUnkeepableApps = Array(Set(Self.knownUnkeepableApps).union(unkeepableApps)).sorted()
                NotificationCenter.default.post(name: .unkeepableSystemItemsChanged, object: nil)
            }
            self.layout = layout
            body(layout)
        }
    }

    // Activates the new restriction before dropping the old one, so switching
    // between collapsed and expanded never flashes the whole bar visible.
    private func activate(_ hold: NativeHold, completion: @escaping (Bool) -> Void) {
        generation += 1
        let generation = self.generation
        inFlightHold = hold
        let allowed = (ownBundleIdentifier.map { [$0] } ?? []) + hold.bundles
        visibility.activate(allowedSystemItems: hold.systemItems,
                            allowedBundleIdentifiers: allowed) { [weak self] result in
            guard let self = self, generation == self.generation else {
                if case .success(let stale) = result { stale.invalidate() }
                return
            }
            self.inFlightHold = nil
            switch result {
            case .success(let newAssertion):
                let old = self.assertion
                self.assertion = newAssertion
                self.assertionBundles = hold.bundles
                self.assertionSystemItems = hold.systemItems
                self.assertionGeneration = generation
                // Any activation that does not carry it replaces what the palette
                // allowed; a re-activation that keeps the app (a launch, a
                // presentation starting) leaves its session open.
                if let allowed = self.temporaryAllow, !hold.bundles.contains(allowed.bundle) {
                    self.temporaryAllow = nil
                }
                old?.invalidate()
                self.watchClock()
                completion(true)
            case .failure(let error):
                // Fail open: never leave icons hidden after an error.
                NSLog("NativeVisibility: activation failed: \(error.localizedDescription)")
                self.releaseAssertion()
                self.presentationHideFailed()
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
        temporaryAllow = nil
        generation += 1
        inFlightHold = nil
        assertion?.invalidate()
        assertion = nil
        watchClock()
    }

    // A start expands the bar the way the arrow does (state, arrow, auto-hide),
    // without bringing Hidden Bar forward, and an expanded bar that still hides the always-hidden section shows it
    // too. A collapse in flight is left to land. Nothing else follows capture.
    private func captureActivityDidChange() {
        let isActive = captureActivity.isActive
        // Presentation mode reads the level at this moment and pauses at once.
        presentationInputsChanged()
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
    // A collapse in flight ignores every other collapse, so one macOS never
    // answers (the section read or the restriction) would leave the arrow and
    // auto-collapse dead (#523, #524). Past this the engine gives up and shows
    // the bar; a healthy collapse takes a second or two.
    static let collapseTimeout: TimeInterval = 10
    var scheduleCollapseTimeout: (TimeInterval, @escaping () -> Void) -> Void = {
        DispatchQueue.main.asyncAfter(deadline: .now() + $0, execute: $1)
    }
    // Set by the controller to re-arm auto-collapse: its timer fired into the
    // collapse that timed out.
    var onCollapseTimedOut: (() -> Void)?
    private var collapseAttempt = 0

    // Leaves the bar as an activation failure does: nothing held, expanded. The
    // dropped generation makes a late answer invalidate itself.
    private func startCollapseTimeout(_ completion: @escaping (CollapseResult) -> Void) {
        collapseAttempt += 1
        let attempt = collapseAttempt
        scheduleCollapseTimeout(Self.collapseTimeout) { [weak self] in
            guard let self = self, attempt == self.collapseAttempt, self.state == .calibrating else { return }
            NSLog("NativeVisibility: macOS did not answer the hide request within \(Int(Self.collapseTimeout)) s; showing the whole menu bar")
            self.revealAll()
            self.state = .expanded
            completion(.unavailable)
            self.onCollapseTimedOut?()
        }
    }
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

    func allowTemporarily(_ bundle: String, completion: @escaping (PaletteLift) -> Void) {
        // A collapse or an activation in flight would be cancelled by another.
        guard state != .calibrating else { return completion(.unavailable) }
        // Nothing held means nothing is hidden.
        guard assertion != nil else { return completion(.alreadyShown) }
        guard generation == assertionGeneration, visibility.isAvailable else { return completion(.unavailable) }
        // Presentation mode keeps its sensitive apps hidden, whatever asks.
        guard !isSensitiveWhilePresenting(bundle) else { return completion(.sensitive) }
        guard !assertionBundles.contains(bundle) else { return completion(.alreadyShown) }
        let before = assertionBundles
        activate(NativeHold(systemItems: assertionSystemItems, bundles: before + [bundle])) { [weak self] succeeded in
            guard let self = self else { return }
            if succeeded {
                self.temporaryAllow = (bundle, before)
                return completion(.lifted)
            }
            // activate released the restriction: nothing is hidden any more.
            self.state = .expanded
            completion(.unavailable)
        }
    }

    func endTemporaryAllow() {
        guard let allowed = temporaryAllow else { return }
        temporaryAllow = nil
        // An expand, a collapse or a section edit since replaced the restriction;
        // what it set stands.
        guard assertion != nil, generation == assertionGeneration, assertionBundles.contains(allowed.bundle) else { return }
        // What is wanted now, which also follows a presentation that started
        // while the app was allowed; the list held before is the fallback.
        let wanted = hold(whenBar: state, layout: layout)
            ?? NativeHold(systemItems: assertionSystemItems, bundles: allowed.before)
        activate(wanted) { _ in }
    }

    private func isSensitiveWhilePresenting(_ bundle: String) -> Bool {
        return holdsPresentationList && sensitiveApps().contains(bundle)
    }

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

    var hiddenSectionBundles: Set<String> {
        return Set(layout?.bundles(in: [.hidden]) ?? [])
    }

    // Set by the controller: the palette's reveal session also keeps a bar the user changed.
    var onUserChangedBar: (() -> Void)?

    func userChangedBar() {
        // The user's own expand or collapse ends the palette's lift: its app must
        // not ride along in every list after this (the session, which stops
        // restoring, never calls endTemporaryAllow).
        temporaryAllow = nil
        notificationCenter.userChangedBar()
        onUserChangedBar?()
    }

    private func clockClicked(at location: CGPoint) {
        // Not while an activation, a section read or a collapse's visibility
        // check is in flight: expanding or lifting now would cancel it, and a
        // cancelled collapse never reports back, leaving the bar stuck calibrating.
        guard assertion != nil, generation == assertionGeneration, state != .calibrating else { return }
        // Presenting: no lift (a flash on the shared screen) and no expand (it
        // would show Notification Center to the room).
        guard !holdsPresentationList else { return }
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
        let lifted = currentHold
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
            // What is wanted now, not what was held: presentation mode may have
            // started while the restriction was lifted.
            guard let wanted = self.hold(whenBar: self.state, layout: self.layout) ?? lifted else { return }
            self.activate(wanted) { [weak self] succeeded in
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
        reconcileHold()
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
        guard pinsSections() else { return }
        let table = pinnedSections.sections
        // An app removed from the table must not come back through an earlier
        // read: an overflowing read borrows from the last complete one, and the
        // resolver would add the app to the table again. A launched app stays.
        let listed = { [launchedSinceRead] (bundle: String) in table[bundle] != nil || launchedSinceRead.contains(bundle) }
        if var complete = lastCompleteLayout {
            complete.sections = complete.sections.filter { listed($0.key) }
            lastCompleteLayout = complete
        }
        guard var layout = layout else { return }
        layout.sections = layout.sections.filter { listed($0.key) }
        for bundle in layout.sections.keys {
            if let pinned = table[bundle] { layout.sections[bundle] = pinned }
        }
        self.layout = layout
        NSLog("NativeVisibility: pinned sections changed; visible \(layout.bundles(in: [.visible])), hidden \(layout.bundles(in: [.hidden])), always hidden \(layout.bundles(in: [.alwaysHidden]))")
        switch state {
        case .collapsed:
            reconcileHold()
        case .expanded:
            applyExpandedPresentation()
        case .calibrating, .unavailable:
            break
        }
    }

    func applicationTerminated(_ bundle: String) {
        launchedSinceRead.remove(bundle)
    }

    // Swaps the held restriction for the one wanted now: it also allows apps
    // placed since it was activated, and follows presentation mode and the
    // sensitive apps. Not while anything is in flight; the collapse or expand
    // that lands calls this again. Every re-activation comes through here, so
    // the list is always computed from the current state, never from the event.
    //
    // Presentation mode supersedes an activation in flight (a swap is safe to
    // replace: the older list is invalidated when it lands); a launch waits.
    private func reconcileHold(superseding: Bool = false) {
        guard assertion != nil, state != .calibrating else { return }
        guard superseding || generation == assertionGeneration else { return }
        guard let wanted = hold(whenBar: state, layout: layout), wanted != (inFlightHold ?? currentHold) else { return }
        NSLog("NativeVisibility: holding \(wanted.bundles.count) apps (was \(assertionBundles.count)); newly allowed \(Set(wanted.bundles).subtracting(assertionBundles).sorted())")
        activate(wanted) { [weak self] succeeded in
            guard let self = self else { return }
            guard !succeeded else {
                // What is wanted may have changed while this was in flight.
                return self.reconcileHold()
            }
            self.state = .expanded
            self.setSeparatorsVisible(true)
        }
    }

    // What a hold in progress or one that has just landed may still owe
    // presentation mode: paused means the bar must not stay collapsed.
    private func settleHold() {
        if presentation.isOn, currentPhase() == .paused, state == .collapsed {
            return liftForCapture()
        }
        reconcileHold()
    }

    var currentHold: NativeHold? {
        return assertion == nil ? nil : NativeHold(systemItems: assertionSystemItems, bundles: assertionBundles)
    }

    // The one place that says what a restriction allows, besides Hidden Bar
    // itself. nil: nothing to hold (no layout read yet, or nothing settled).
    //
    // The app the palette lets show for its open session stays in the list through
    // every re-activation (a launch, a presentation starting), unless it is a
    // sensitive app while presenting.
    private func hold(whenBar bar: MenuBarEngineState, layout: MenuBarLayout?) -> NativeHold? {
        guard let base = baseHold(whenBar: bar, layout: layout) else { return nil }
        guard let allowed = temporaryAllow, !isSensitiveWhilePresenting(allowed.bundle),
              !base.bundles.contains(allowed.bundle) else { return base }
        return NativeHold(systemItems: base.systemItems, bundles: base.bundles + [allowed.bundle])
    }

    private func baseHold(whenBar bar: MenuBarEngineState, layout: MenuBarLayout?) -> NativeHold? {
        let presenting = holdsPresentationList
        switch bar {
        case .collapsed:
            if presenting {
                return NativeHold(systemItems: Self.presentationSystemItems, bundles: [])
            }
            return layout.map { NativeHold(systemItems: Self.systemItemsToKeep, bundles: $0.bundles(in: [.visible])) }
        case .expanded:
            let shown = layout?.bundles(in: [.visible, .hidden])
            if presenting {
                // The sensitive apps stay hidden, also when the user put one in
                // the visible section.
                let sensitive = sensitiveApps()
                guard let shown = shown else { return NativeHold(systemItems: Self.presentationSystemItems, bundles: []) }
                return NativeHold(systemItems: Self.presentationSystemItems, bundles: shown.filter { !sensitive.contains($0) })
            }
            return shown.map { NativeHold(systemItems: Self.systemItemsToKeep, bundles: $0) }
        case .calibrating, .unavailable:
            return nil
        }
    }

    // MARK: - Presentation mode

    // Starts and stops come from the user (shortcut, arrow menu, capsule), the
    // mirror trigger from the display notice, and the pause from the capture
    // monitor. Each only records its input; the phase decides the rest.
    var isPresentationOn: Bool { return presentation.isOn }
    var presentationCause: PresentationCause? { return presentation.cause }

    func startPresentation() {
        presentation.startManually()
        presentationInputsChanged()
    }

    func stopPresentation() {
        presentation.stop()
        presentationInputsChanged()
    }

    // "Hide again" on the paused capsule: the camera or microphone is still on and
    // the user wants the list held anyway. A later capture start pauses again.
    func resumePresentationHiding() {
        guard presentation.isOn, currentPhase() == .paused else { return }
        resumePresentationHiding(collapsing: true)
    }

    private func resumePresentationHiding(collapsing: Bool) {
        presentation.resumeHiding()
        if collapsing {
            presentationInputsChanged()
        } else {
            notePhaseChange()
        }
    }

    func presentationMirrorChanged(_ mirror: PresentationMirror?) {
        guard mirror != presentation.mirror else { return }
        presentation.mirrorChanged(mirror)
        presentationInputsChanged()
    }

    // The sensitive set changed in Preferences: apply it to the held list.
    func sensitiveAppsDidChange() {
        // Only a presentation holds a list that depends on them; every other
        // preference change reaches this too and must leave the hold alone.
        guard holdsPresentationList else { return }
        reconcileHold(superseding: true)
    }

    // The phase, with the capture level read at this moment.
    func currentPhase() -> PresentationPhase {
        // Off is the common case: read the monitor only while a mode is on.
        // The pause follows the same switch as the main bar (1.12): "show the whole
        // bar when a camera or microphone turns on". Off, it never pauses.
        return presentation.resolve(captureActive: presentation.isOn && captureActivity.isActive,
                                    pausesForCapture: expandsWhenCaptureStarts(), now: clockNow())
    }

    // Presenting and still trying to hide (also after a refusal, so the next
    // collapse tries the strict list again).
    private var holdsPresentationList: Bool {
        let phase = currentPhase()
        return phase == .presenting || phase == .couldNotHide
    }

    // Apps a restriction held now keeps hidden although Hidden Bar knows them.
    var presentationHiddenBundles: [String] {
        guard assertion != nil, let layout = layout else { return [] }
        return layout.sections.keys.filter { !assertionBundles.contains($0) }.sorted()
    }

    private func presentationInputsChanged() {
        let previous = seenPhase
        // Reads the capture level first: the resume wait counts from it.
        let phase = currentPhase()
        scheduleResumeCheck()
        guard phase != previous else { return }
        seenPhase = phase
        NSLog("NativeVisibility: presentation mode \(previous) -> \(phase)")
        onPresentationChange?(phase)
        switch phase {
        case .paused:
            liftForCapture()
        case .presenting, .couldNotHide:
            // On, or on again after a pause: the bar goes back to hidden.
            if state == .collapsed {
                reconcileHold(superseding: true)
            } else if state == .expanded || state == .unavailable {
                if let collapseBar = collapseBar { collapseBar() } else { collapse { _ in } }
            }
        case .off:
            if state == .expanded {
                hidesAlwaysHiddenSection ? reconcileHold(superseding: true) : revealAll()
            } else if state == .collapsed, hold(whenBar: .collapsed, layout: layout) == nil {
                // No read to take the normal list from: show the bar rather than
                // leave the strict list held with the mode off.
                if let expandBar = expandBar { expandBar() } else { expand() }
            } else {
                reconcileHold(superseding: true)
            }
        }
    }

    // A microphone or camera turned on: the restriction hides the capsule naming
    // the app that uses it, so it is lifted once.
    private func liftForCapture() {
        NSLog("NativeVisibility: presentation mode paused: a microphone or camera is on; showing the whole menu bar")
        if state == .collapsed {
            if let expandBar = expandBarForCapture { expandBar() } else { expand() }
        }
        if state == .expanded {
            revealAll()
        }
    }

    // Capture goes quiet before the resume delay ends, so no event follows it.
    private func scheduleResumeCheck() {
        guard let wait = presentation.resumeWait(now: clockNow()) else { return }
        scheduleClockStep(wait + 0.05) { [weak self] in
            self?.presentationInputsChanged()
        }
    }

    // A hold that was meant to hide everything did not land: icons are showing,
    // and the capsule must say so instead of "Presenting".
    private func presentationHideFailed() {
        guard holdsPresentationList else { return }
        presentation.hideDidFail()
        notePhaseChange()
    }

    private func collapseFinished(_ result: CollapseResult) {
        guard presentation.isOn else { return }
        switch result {
        case .collapsed:
            presentation.hideDidSucceed()
        case .unavailable:
            if holdsPresentationList { presentation.hideDidFail() }
        }
        notePhaseChange()
    }

    private func notePhaseChange() {
        let phase = currentPhase()
        guard phase != seenPhase else { return }
        seenPhase = phase
        onPresentationChange?(phase)
    }

    // No Accessibility, so no layout: the strict list needs only Hidden Bar's own
    // bundle, so a presentation still hides.
    private func holdPresentationListUnread(_ completion: @escaping (CollapseResult) -> Void) {
        guard let wanted = hold(whenBar: .collapsed, layout: nil) else { return completion(.unavailable) }
        state = .calibrating
        startCollapseTimeout(completion)
        activate(wanted) { [weak self] succeeded in
            guard let self = self else { return }
            self.state = succeeded ? .collapsed : .expanded
            if succeeded { self.setSeparatorsVisible(false) }
            completion(succeeded ? .collapsed : .unavailable)
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
    // Same, for apps run from outside an Applications folder, by name.
    static private(set) var knownUnkeepableApps: [String] = []

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
            "temporaryAllow": temporaryAllow?.bundle ?? NSNull(),
            "pinsSections": pinsSections(),
            "pinnedSections": pinnedSections.sections.mapValues { String(describing: $0) },
            "observedSections": sectionMemory.sections.mapValues { String(describing: $0) },
            "ignoredDrags": ignoredDrags().sorted(),
            "launchedSinceRead": launchedSinceRead.sorted(),
            "presentationPhase": String(describing: seenPhase),
            "presentationOn": presentation.isOn,
            "presentationCause": presentation.cause.map { String(describing: $0) } ?? NSNull(),
            "allowedSystemItemCount": assertion == nil ? 0 : assertionSystemItems.count
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
