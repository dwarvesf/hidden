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
    private let expandCollapseStatusBar = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let separateStatusBar = NSStatusBar.system.statusItem(withLength: CGFloat(20))
    private let terminateStatusBar = NSStatusBar.system.statusItem(withLength: CGFloat(20))
    
    private let hiddenIconLength: CGFloat = 0
    private let normalIconLength: CGFloat = 20
    private var normalStatusBarIconLength: CGFloat {
        return self.areSeparatorsHidden ? self.hiddenIconLength : self.normalIconLength
    }
    private let collapseStatusBarIconLength: CGFloat = 10000
    
    private let menu = NSMenu()
    
    private let imgIconLine = NSImage(named:NSImage.Name("ic_line"))
    private let imgIconCollapse = NSImage(named:NSImage.Name("ic_collapse"))
    private let imgIconExpand = NSImage(named:NSImage.Name("ic_expand"))
    
    private var isCollapsed: Bool {
        return self.separateStatusBar.length == self.collapseStatusBarIconLength
    }
    
    private var areSeparatorsHidden: Bool {
        return self.terminateStatusBar.length == self.collapseStatusBarIconLength
    }
    
    private var isValidPosition: Bool {
        guard
            let expandBarButtonX = self.expandCollapseStatusBar.button?.getOrigin?.x,
            let separateBarButtonX = self.separateStatusBar.button?.getOrigin?.x
            else {return false}
        
        return expandBarButtonX >= separateBarButtonX
    }
    
    private var isValidTogglablePosition: Bool {
        guard
            let separateBarButtonX = self.separateStatusBar.button?.getOrigin?.x,
            let terminateBarButtonX = self.terminateStatusBar.button?.getOrigin?.x
            else {return false}
        
        return separateBarButtonX >= terminateBarButtonX
    }
    
    //MARK: - Methods
    init() {
        setupUI()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: {
            self.collapseMenuBar()
        })
        
        autoCollapseIfNeeded()
        autoToggleSeparatorsIfNeeded()
    }
    
    private func setupUI() {
        self.setupContextMenu()
        
        if let button = separateStatusBar.button {
            button.image = self.imgIconLine
        }
        
        if let button = terminateStatusBar.button {
            button.image = self.imgIconLine
            button.appearsDisabled = true
        }
        
        if let button = expandCollapseStatusBar.button {
            button.image = self.imgIconCollapse
            button.target = self
            
            button.action = #selector(self.statusBarButtonClicked(sender:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }
    
    @objc func statusBarButtonClicked(sender: NSStatusBarButton) {
        if NSApp.currentEvent!.type == NSEvent.EventType.leftMouseUp {
            expandCollapseIfNeeded(sender)
        } else {
            expandCollapseStatusBar.popUpMenu(self.menu)
        }
    }
    
    @objc func expandCollapseIfNeeded(_ sender: NSStatusBarButton?) {
        self.isCollapsed ? self.expandMenubar() : self.collapseMenuBar()
    }
    
    private func collapseMenuBar() {
        guard self.isValidPosition && !self.isCollapsed else {
            autoCollapseIfNeeded()
            return
        }
        
        separateStatusBar.length = self.collapseStatusBarIconLength
        if let button = expandCollapseStatusBar.button {
            button.image = self.imgIconExpand
        }

    }
    
    private func expandMenubar() {
        guard self.isCollapsed else {return}
        separateStatusBar.length = normalStatusBarIconLength
        if let button = expandCollapseStatusBar.button {
            button.image = self.imgIconCollapse
        }
        
        autoCollapseIfNeeded()
    }
    
    private func autoCollapseIfNeeded() {
        guard Preferences.isAutoHide else {return}
        
        startTimerToAutoHide()
    }
    
    private func startTimerToAutoHide() {
        timer?.invalidate()
        self.timer = Timer.scheduledTimer(withTimeInterval: Preferences.numberOfSecondForAutoHide, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.collapseMenuBar()
            }
        }
    }
    
    private func setupContextMenu() {
        let toggleItem = NSMenuItem(title: "Toggle Separators", action: #selector(toggleSeparators), keyEquivalent: "")
        toggleItem.target = self
        self.menu.addItem(toggleItem)
        
        let prefItem = NSMenuItem(title: "Preferences...".localized, action: #selector(openPreferenceViewControllerIfNeeded), keyEquivalent: "")
        prefItem.target = self
        self.menu.addItem(prefItem)

        self.menu.addItem(NSMenuItem.separator())
        self.menu.addItem(NSMenuItem(title: "Quit".localized, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }
    
    @objc func openPreferenceViewControllerIfNeeded() {
        Util.showPrefWindow()
    }
    
    @objc func toggleSeparators() {
        if self.isCollapsed {
            expandMenubar()
        }
        
        self.areSeparatorsHidden ? self.showSeparators() : self.hideSeparators()
    }
    
    private func hideSeparators() {
        guard self.isValidTogglablePosition && !self.areSeparatorsHidden else { return }
        
        terminateStatusBar.length = collapseStatusBarIconLength
        separateStatusBar.length = normalStatusBarIconLength
        
        Preferences.areSeparatorsHidden = true
    }
    
    private func showSeparators() {
        guard self.areSeparatorsHidden else {return}
        
        terminateStatusBar.length = normalIconLength
        separateStatusBar.length = normalStatusBarIconLength
        
        Preferences.areSeparatorsHidden = false
    }
    
    private func autoToggleSeparatorsIfNeeded() {
        guard Preferences.areSeparatorsHidden && !self.areSeparatorsHidden else {return}
        
        self.hideSeparators()
    }
}
