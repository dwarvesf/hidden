//
//  PreferencesWindowController.swift
//  Hidden Bar
//
//  Created by Phuc Le Dien on 2/22/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import Cocoa

class PreferencesWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    
    static let shared: PreferencesWindowController = {
        let wc = NSStoryboard(name:"Main", bundle: nil).instantiateController(withIdentifier: "MainWindow") as! PreferencesWindowController
        return wc
    }()
    
    private let preferencesVC = PreferencesViewController.initWithStoryboard()
    private let aboutVC = AboutViewController.initWithStoryboard()
    private lazy var tabs: SettingsTabViewController = {
        let controller = SettingsTabViewController()
        controller.tabStyle = .unspecified
        controller.tabView.tabViewType = .noTabsNoBorder
        controller.onSelectionChange = { [weak self] index in
            self?.preferencesVC.cancelShortcutRecording()
            self?.tabSelector.selectedSegment = index
        }
        let general = NSTabViewItem(viewController: preferencesVC)
        general.label = "General".localized
        general.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: general.label)
        let about = NSTabViewItem(viewController: aboutVC)
        about.label = "About".localized
        about.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: about.label)
        controller.addTabViewItem(general)
        controller.addTabViewItem(about)
        return controller
    }()

    private let tabsIdentifier = NSToolbarItem.Identifier("settingsTabs")
    private lazy var tabSelector: NSSegmentedControl = {
        let control = NSSegmentedControl(labels: ["General".localized, "About".localized],
                                         trackingMode: .selectOne,
                                         target: self, action: #selector(selectTab(_:)))
        control.selectedSegment = 0
        control.controlSize = .regular
        control.segmentDistribution = .fillEqually
        control.segmentStyle = .automatic
        // Use the system capsule geometry; older SDKs keep their native appearance.
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            control.borderShape = .capsule
        }
        #endif
        #if compiler(>=6.4)
        if #available(macOS 27.0, *) {
            control.role = .tabs
        }
        #endif
        return control
    }()

    @objc private func selectTab(_ sender: NSSegmentedControl) {
        tabs.selectedTabViewItemIndex = sender.selectedSegment
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, tabsIdentifier, .flexibleSpace]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [tabsIdentifier, .flexibleSpace]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard itemIdentifier == tabsIdentifier else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.view = tabSelector
        item.isBordered = false
        item.label = "Preferences...".localized
        return item
    }

    private var activePreferences: PreferencesViewController? {
        tabs.selectedTabViewItemIndex == 0 ? preferencesVC : nil
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        guard let window else { return }
        window.styleMask.remove(.fullSizeContentView)
        window.contentViewController = tabs
        let toolbar = NSToolbar(identifier: "preferences")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.sizeMode = .small
        toolbar.centeredItemIdentifiers = [tabsIdentifier]
        window.toolbarStyle = .unifiedCompact
        window.toolbar = toolbar
    }

    func windowWillClose(_ notification: Notification) {
        preferencesVC.cancelShortcutRecording()
    }

    func windowDidResignKey(_ notification: Notification) {
        preferencesVC.cancelShortcutRecording()
    }

    override func keyDown(with event: NSEvent) {
        if let vc = activePreferences, vc.listening {
            if event.keyCode == 53 { // Escape cancels without clearing the saved shortcut.
                vc.cancelShortcutRecording()
            } else {
                vc.updateGlobalShortcut(event)
            }
            return
        }
        super.keyDown(with: event)
    }

    // Cmd+W closes the prefs window. The main menu has no File > Close item, so
    // the key equivalent falls through to the responder chain. While the
    // shortcut recorder is listening it keeps the event, so the user can still
    // bind Cmd+W as the global hotkey.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let vc = activePreferences, vc.listening {
            if event.keyCode == 53 {
                vc.cancelShortcutRecording()
            } else {
                vc.updateGlobalShortcut(event)
            }
            return true
        }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods.isSubset(of: [.command, .shift]),
           mods.contains(.command),
           event.charactersIgnoringModifiers == "w" {
            window?.performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
    
    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        if let vc = activePreferences, vc.listening {
            vc.updateModiferFlags(event)
        }
    }
    
}

private final class SettingsTabViewController: NSTabViewController {
    var onSelectionChange: (Int) -> Void = { _ in }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        if let tabViewItem {
            onSelectionChange(tabView.indexOfTabViewItem(tabViewItem))
        }
        super.tabView(tabView, didSelect: tabViewItem)
    }
}
