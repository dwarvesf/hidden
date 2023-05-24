//
//  ContextMenuController.swift
//  Hidden Bar
//
//  Created by 上原葉 on 5/21/23.
//  Copyright © 2023 Dwarves Foundation. All rights reserved.
//

import AppKit

class ContextMenuController {
    class ContextMenuDelegate:NSObject, NSMenuDelegate {
        func confinementRect(for menu: NSMenu, on screen: NSScreen?) -> NSRect {
            guard let lscreen = screen else { return NSZeroRect }
            return lscreen.visibleFrame
        }
    }
    private static let delegate = ContextMenuDelegate()
    private static let instance = ContextMenuController()
    private let contextMenu: NSMenu
    private let prefButton: NSMenuItem
    private let editToggle: NSMenuItem
    private let quitButton: NSMenuItem
    private let seperator1 = NSMenuItem.separator()
    private let seperator2 = NSMenuItem.separator()
    private init() {
        let menu = NSMenu()
        
        let nPrefButton = NSMenuItem(title: "Preferences...".localized, action: #selector(showPreference), keyEquivalent: ",")
        nPrefButton.tag = 0
        
        
        let nEditToggle = NSMenuItem(title: "Edit Mode".localized, action: #selector(toggleEdit), keyEquivalent: "e")
        nEditToggle.tag = 1
        
        let nQuitButton = NSMenuItem(title: "Quit".localized, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        nQuitButton.tag = 2
        
        contextMenu = menu
        prefButton = nPrefButton
        editToggle = nEditToggle
        quitButton = nQuitButton
    }
    
    private func updateMenu() {
        editToggle.state = (Preferences.isEditMode) ? .on : .off
    }
    
    public static func setup() {
        instance.prefButton.target = instance
        instance.editToggle.target = instance
        instance.contextMenu.addItem(instance.prefButton)
        instance.contextMenu.addItem(instance.seperator1)
        instance.contextMenu.addItem(instance.editToggle)
        instance.contextMenu.addItem(instance.seperator2)
        instance.contextMenu.addItem(instance.quitButton)
        
        instance.contextMenu.delegate = delegate
        
        NotificationCenter.default.addObserver(forName: NotificationNames.prefsChanged, object: nil, queue: nil) {[] _ in
            instance.updateMenu()
        }
        instance.updateMenu()
    }
    
    public static func showContextMenu(_ sender: NSStatusBarButton) {
        instance.contextMenu.popUp(positioning: nil, at: .init(x: sender.bounds.minX, y: sender.bounds.minY), in: sender)
    }
    
    @objc func showPreference() {
        Util.showPrefWindow()
    }
    @objc func toggleEdit() {
        Preferences.isEditMode = !Preferences.isEditMode
    }

    
}

