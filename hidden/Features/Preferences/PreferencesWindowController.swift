//
//  PreferencesWindowController.swift
//  Hidden Bar
//
//  Created by Phuc Le Dien on 2/22/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import Cocoa

/// Whether the notch overflow feature (menu of icons behind the notch) applies.
/// macOS 27 never puts an icon behind the notch, it moves them into its own «
/// button, so there is never anything to list there.
enum NotchOverflowSupport {
    static func isAvailable(osMajorVersion: Int, hasNotch: Bool) -> Bool {
        hasNotch && osMajorVersion < 27
    }

    static var isAvailableNow: Bool {
        isAvailable(osMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
                    hasNotch: NotchOverflowController.hasNotch)
    }
}

/// What the Settings window needs to know about the running app. The live
/// value comes from the build flags and the real checks; a snapshot or a test
/// can fix any part of it.
struct SettingsContext {
    var build: SettingsBuild = .current
    var osMajorVersion: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
    var hasNotch: Bool = NotchOverflowController.hasNotch
    var statusOverride: SettingsStatus?
    /// Draw the preview with this always-hidden state instead of the stored one.
    var previewAlwaysHidden: Bool?
    var menuBarAppsAvailable: Bool = MenuBarAppsPane.makeViewController != nil
    /// Snapshots and tests read the find shortcut from here instead of the real preferences.
    var shortcutFixtureDefaults: UserDefaults?

    static var live: SettingsContext { SettingsContext() }

    var showsNotchOverflow: Bool { NotchOverflowSupport.isAvailable(osMajorVersion: osMajorVersion, hasNotch: hasNotch) }

    var usesNativeEngine: Bool { build.usesNativeEngine(osMajorVersion: osMajorVersion) }

    var visibleTabs: [SettingsTab] {
        SettingsTab.visibleTabs(build: build, osMajorVersion: osMajorVersion, menuBarAppsAvailable: menuBarAppsAvailable)
    }

    var status: SettingsStatus {
        statusOverride ?? SettingsStatus.resolve(build: build, osMajorVersion: osMajorVersion,
                                                 runsFromApplicationsFolder: MenuBarEngineFactory.runsFromApplicationsFolder(),
                                                 accessibilityMissing: AccessibilityPermission.shared.isMissing)
    }
}

final class SettingsWindow: NSWindow {
    #if DEBUG
    /// Snapshots draw the window as the active one without making it key.
    var drawsAsKey = false
    override var isKeyWindow: Bool { drawsAsKey || super.isKeyWindow }
    override var isMainWindow: Bool { drawsAsKey || super.isMainWindow }
    #endif
}

/// The slot for the Icons pane. The pinned sections feature (beta)
/// sets this at launch; until then the tab does not exist.
enum MenuBarAppsPane {
    static var makeViewController: (() -> NSViewController)?
}

/// Settings: a tab control at the top swaps the panes below it.
class PreferencesWindowController: NSWindowController {

    private static var sharedInstance: PreferencesWindowController?

    static let shared: PreferencesWindowController = {
        let controller = PreferencesWindowController(context: .live)
        sharedInstance = controller
        return controller
    }()

    // Checking auto-hide must not build a window the user has never opened.
    static var isVisible: Bool {
        guard let controller = sharedInstance, controller.isWindowLoaded else { return false }
        return controller.window?.isVisible ?? false
    }

    let context: SettingsContext
    let tabs: [SettingsTab]
    private(set) var selectedTab: SettingsTab = .general
    private var panes: [SettingsTab: NSViewController] = [:]
    /// Text-only tabs centered at the top, level with the traffic lights, like
    /// the old "General | About" pill. No toolbar, so no glass platters.
    let tabControl = NSSegmentedControl()
    private let paneHost = NSView()
    private var paneHeight: NSLayoutConstraint?
    static let tabBarHeight: CGFloat = 44
    /// The tallest the window gets. A pane that needs more scrolls inside it, in
    /// `paneScroll`, so the window still fits a laptop screen.
    static let maxWindowHeight: CGFloat = 720
    /// Holds a pane taller than the window allows; empty otherwise.
    let paneScroll = NSScrollView()
    private let paneScrollContent = TopLeftPaneContent()

    /// The pane on screen.
    var currentPane: NSViewController { pane(selectedTab) }

    init(context: SettingsContext) {
        self.context = context
        self.tabs = context.visibleTabs
        let width = SettingsMetrics.contentWidth + 2 * SettingsMetrics.sideInset
        let window = SettingsWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 400),
                                    styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                                    backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        super.init(window: window)

        tabControl.segmentCount = tabs.count
        for (index, tab) in tabs.enumerated() {
            tabControl.setLabel(tab.titleKey.localized, forSegment: index)
        }
        tabControl.trackingMode = .selectOne
        tabControl.segmentStyle = .automatic
        tabControl.identifier = NSUserInterfaceItemIdentifier("settingsTabs")
        tabControl.target = self
        tabControl.action = #selector(tabClicked(_:))

        let root = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 400))
        for view in [tabControl, paneHost] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        let height = paneHost.heightAnchor.constraint(equalToConstant: 300)
        paneHeight = height
        NSLayoutConstraint.activate([
            tabControl.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            // The titlebar is 28 pt; this centers the control on the traffic lights' row and below.
            tabControl.topAnchor.constraint(equalTo: root.topAnchor, constant: 8),
            paneHost.topAnchor.constraint(equalTo: root.topAnchor, constant: Self.tabBarHeight),
            paneHost.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            paneHost.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            paneHost.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            root.widthAnchor.constraint(equalToConstant: width),
            height,
        ])
        window.contentView = root
        select(.general, animate: false)
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func pane(_ tab: SettingsTab) -> NSViewController {
        if let pane = panes[tab] { return pane }
        let pane: NSViewController
        switch tab {
        case .general: pane = PreferencesViewController(context: context)
        case .menuBarApps: pane = MenuBarAppsPane.makeViewController?() ?? NSViewController(nibName: nil, bundle: nil)
        case .appearance: pane = AppearanceSettingsViewController(context: context)
        case .advanced: pane = AdvancedSettingsViewController(context: context)
        case .about: pane = AboutViewController(context: context)
        }
        panes[tab] = pane
        return pane
    }

    func select(_ tab: SettingsTab, animate: Bool = true) {
        guard let index = tabs.firstIndex(of: tab), let window else { return }
        let old = pane(selectedTab)
        selectedTab = tab
        let controller = pane(tab)
        tabControl.selectedSegment = index
        // Hidden in the titlebar, but still the window's name in the Window menu and to VoiceOver.
        window.title = tab.titleKey.localized

        let fitting = controller.view.fittingSize
        let scrolls = fitting.height > Self.maxWindowHeight - Self.tabBarHeight
        let size = NSSize(width: fitting.width, height: scrolls ? Self.maxWindowHeight - Self.tabBarHeight : fitting.height)
        old.view.removeFromSuperview()
        controller.view.removeFromSuperview()
        detachPaneScroll()
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        let host: NSView = scrolls ? attachPaneScroll(for: controller.view) : controller.view
        paneHost.addSubview(host)
        host.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: paneHost.topAnchor),
            host.leadingAnchor.constraint(equalTo: paneHost.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: paneHost.trailingAnchor),
        ] + (scrolls ? [host.bottomAnchor.constraint(equalTo: paneHost.bottomAnchor)] : []))
        paneHeight?.constant = size.height
        // Resize around the new pane, keeping the top edge where it was.
        let contentSize = NSSize(width: window.frame.width, height: Self.tabBarHeight + size.height)
        let frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize))
        var newFrame = window.frame
        newFrame.origin.y += newFrame.height - frame.height
        newFrame.size = frame.size
        window.setFrame(newFrame, display: true, animate: animate && window.isVisible)
        (controller as? SettingsPaneController)?.refreshAll()
    }

    /// Puts `pane` in a vertical scroll view the width of the window, pinned to
    /// the top, and returns the scroll view.
    private func attachPaneScroll(for pane: NSView) -> NSView {
        paneScroll.hasVerticalScroller = true
        paneScroll.hasHorizontalScroller = false
        paneScroll.autohidesScrollers = true
        paneScroll.scrollerStyle = .overlay
        paneScroll.drawsBackground = false
        paneScroll.borderType = .noBorder
        paneScroll.documentView = paneScrollContent
        paneScrollContent.translatesAutoresizingMaskIntoConstraints = false
        pane.translatesAutoresizingMaskIntoConstraints = false
        paneScrollContent.addSubview(pane)
        NSLayoutConstraint.activate([
            pane.topAnchor.constraint(equalTo: paneScrollContent.topAnchor),
            pane.bottomAnchor.constraint(equalTo: paneScrollContent.bottomAnchor),
            pane.leadingAnchor.constraint(equalTo: paneScrollContent.leadingAnchor),
            pane.trailingAnchor.constraint(equalTo: paneScrollContent.trailingAnchor),
            paneScrollContent.topAnchor.constraint(equalTo: paneScroll.contentView.topAnchor),
            paneScrollContent.leadingAnchor.constraint(equalTo: paneScroll.contentView.leadingAnchor),
            paneScrollContent.trailingAnchor.constraint(equalTo: paneScroll.contentView.trailingAnchor),
        ])
        paneScroll.contentView.scroll(to: .zero)
        return paneScroll
    }

    private func detachPaneScroll() {
        paneScroll.removeFromSuperview()
        paneScroll.documentView = nil
    }

    @objc private func tabClicked(_ sender: NSSegmentedControl) {
        guard tabs.indices.contains(sender.selectedSegment) else { return }
        select(tabs[sender.selectedSegment])
    }

    // MARK: Keys

    // Cmd+W closes the prefs window. The main menu has no File > Close item, so
    // the key equivalent falls through to the responder chain. While a shortcut
    // recorder is listening it keeps the event, so the user can still bind
    // Cmd+W as a global hotkey.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let listening = ShortcutRecorderRow.isRecording
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Cmd+1...Cmd+5 pick a tab, as in other settings windows.
        if !listening, mods == .command, let digit = event.charactersIgnoringModifiers.flatMap(Int.init),
           tabs.indices.contains(digit - 1) {
            select(tabs[digit - 1])
            return true
        }
        if !listening,
           mods.isSubset(of: [.command, .shift]),
           mods.contains(.command),
           event.charactersIgnoringModifiers == "w" {
            window?.performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// A view whose origin is at the top left, so a scrolled pane starts at its top.
class TopLeftPaneContent: NSView {
    override var isFlipped: Bool { true }
}
