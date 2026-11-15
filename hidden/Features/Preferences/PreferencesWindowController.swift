//
//  PreferencesWindowController.swift
//  Hidden Bar
//
//  Created by Phuc Le Dien on 2/22/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import Cocoa

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

    static var live: SettingsContext { SettingsContext() }

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

/// The slot for the Menu Bar Apps pane. The pinned sections feature (beta)
/// sets this at launch; until then the tab does not exist.
enum MenuBarAppsPane {
    static var makeViewController: (() -> NSViewController)?
}

/// Toolbar panes, System Settings style: the window title names the pane.
class PreferencesWindowController: NSWindowController, NSToolbarDelegate {

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

    init(context: SettingsContext) {
        self.context = context
        self.tabs = context.visibleTabs
        let window = SettingsWindow(contentRect: NSRect(x: 0, y: 0, width: SettingsMetrics.contentWidth + 2 * SettingsMetrics.sideInset, height: 400),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .preference
        super.init(window: window)
        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
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
        guard tabs.contains(tab), let window else { return }
        selectedTab = tab
        let controller = pane(tab)
        window.toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier(tab.rawValue)
        window.title = tab.titleKey.localized
        // Resize around the new pane, keeping the top edge where it was.
        let size = controller.view.fittingSize
        controller.view.setFrameSize(size)
        let frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        var newFrame = window.frame
        newFrame.origin.y += newFrame.height - frame.height
        newFrame.size = frame.size
        window.contentViewController = nil
        window.setFrame(newFrame, display: true, animate: animate && window.isVisible)
        window.contentViewController = controller
    }

    @objc private func toolbarItemClicked(_ sender: NSToolbarItem) {
        guard let tab = SettingsTab(rawValue: sender.itemIdentifier.rawValue) else { return }
        select(tab)
    }

    // MARK: NSToolbarDelegate

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        tabs.map { NSToolbarItem.Identifier($0.rawValue) }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let tab = SettingsTab(rawValue: itemIdentifier.rawValue) else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = tab.titleKey.localized
        item.image = NSImage(systemSymbolName: tab.symbolName, accessibilityDescription: item.label)
        // Plain item; macOS 26 and later wrap each one in the system's glass platter.
        item.isBordered = false
        item.target = self
        item.action = #selector(toolbarItemClicked(_:))
        return item
    }

    // MARK: Keys

    private var general: PreferencesViewController? {
        window?.contentViewController as? PreferencesViewController
    }

    override func keyDown(with event: NSEvent) {
        super.keyDown(with: event)
        if let vc = general, vc.listening {
            vc.updateGlobalShortcut(event)
        }
    }

    // Cmd+W closes the prefs window. The main menu has no File > Close item, so
    // the key equivalent falls through to the responder chain. While the
    // shortcut recorder is listening it keeps the event, so the user can still
    // bind Cmd+W as the global hotkey.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let listening = general?.listening ?? false
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if !listening,
           mods.isSubset(of: [.command, .shift]),
           mods.contains(.command),
           event.charactersIgnoringModifiers == "w" {
            window?.performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        if let vc = general, vc.listening {
            vc.updateModiferFlags(event)
        }
    }
}
