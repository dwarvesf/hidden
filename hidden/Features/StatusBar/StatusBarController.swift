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
    private var timer : Timer?
    private var mouseMovementHandler: MouseMovementHandler!
    
    //MARK: - BarItems
    private let expandCollapseStatusBar = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let separateStatusBar = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let terminateStatusBar = NSStatusBar.system.statusItem(withLength: Preferences.alwaysHiddenSectionEnabled ? 20 : 0)
    
    private var normalSeparateStatusBarIconLength: CGFloat { return Preferences.areSeparatorsHidden ? 0 : 20 }
    private let collapseSeparateStatusBarIconLength: CGFloat = 10000
    
    private let normalTerminateStatusBarIconLength: CGFloat = Preferences.alwaysHiddenSectionEnabled ? 20 : 0
    private let collapseTerminateStatusBarIconLength: CGFloat = Preferences.alwaysHiddenSectionEnabled ? 10000 : 0
    
    private let imgIconLine = NSImage(named:NSImage.Name("ic_line"))
    private let imgIconCollapse = NSImage(named:NSImage.Name("ic_collapse"))
    private let imgIconExpand = NSImage(named:NSImage.Name("ic_expand"))
    
    private var isCollapsed: Bool {
        return self.separateStatusBar.length == self.collapseSeparateStatusBarIconLength
    }
    
    private var isValidPosition: Bool {
        guard
            let expandBarButtonX = self.expandCollapseStatusBar.button?.getOrigin?.x,
            let separateBarButtonX = self.separateStatusBar.button?.getOrigin?.x
            else {return false}
        
        return expandBarButtonX >= separateBarButtonX
    }
    
    private var isValidTogglablePosition: Bool {
        if !Preferences.alwaysHiddenSectionEnabled { return true }
        
        guard
            let separateBarButtonX = self.separateStatusBar.button?.getOrigin?.x,
            let terminateBarButtonX = self.terminateStatusBar.button?.getOrigin?.x
            else {return false}
            
        return separateBarButtonX >= terminateBarButtonX
    }
    
    //MARK: - Methods
    init() {
        
        setupUI()
        
        mouseMovementHandler = MouseMovementHandler(expandHandler: expandMenubar, collapseHandler: collapseMenuBar)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: {
            self.collapseMenuBar()
        })
        
        if Preferences.areSeparatorsHidden {hideSeparators()}
        autoCollapseIfNeeded()
    }
    
    private func setupUI() {
        if let button = separateStatusBar.button {
            button.image = self.imgIconLine
        }
        
        if let button = terminateStatusBar.button {
            button.image = self.imgIconLine
            button.appearsDisabled = true
        }
        
        let menu = self.getContextMenu()
        separateStatusBar.menu = menu
        terminateStatusBar.menu = menu
        updateMenuTitles()
        
        if let button = expandCollapseStatusBar.button {
            button.image = self.imgIconCollapse
            button.target = self
            
            button.action = #selector(self.statusBarButtonClicked(sender:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        expandCollapseStatusBar.autosaveName = "hiddenbar_expandcollapse";
        separateStatusBar.autosaveName = "hiddenbar_separate";
        terminateStatusBar.autosaveName = "hiddenbar_terminate";
    }
    
    @objc func statusBarButtonClicked(sender: NSStatusBarButton) {
        if let event = NSApp.currentEvent {
            
            let isOptionKeyPressed = event.modifierFlags.contains(NSEvent.ModifierFlags.option)
            
            if event.type == NSEvent.EventType.leftMouseUp && !isOptionKeyPressed{
                self.expandCollapseIfNeeded()
            } else {
                self.toggleSeparators()
            }
        }
    }
    
    func toggleSeparators() {
        Preferences.areSeparatorsHidden ? self.showSeparators() : self.hideSeparators()
        
        if self.isCollapsed {self.expandMenubar()}
    }
    
    private func showSeparators() {
        Preferences.areSeparatorsHidden = false
        
        if !self.isCollapsed {
            self.separateStatusBar.length = self.normalSeparateStatusBarIconLength
        }
        
        self.terminateStatusBar.length = self.normalTerminateStatusBarIconLength
    }
    
    private func hideSeparators() {
        guard self.isValidTogglablePosition else {return}
        
        Preferences.areSeparatorsHidden = true
        
        if !self.isCollapsed {
            self.separateStatusBar.length = self.normalSeparateStatusBarIconLength
        }
        
        self.terminateStatusBar.length = self.collapseTerminateStatusBarIconLength
    }
    
    func expandCollapseIfNeeded() {
        self.isCollapsed ? self.expandMenubar() : self.collapseMenuBar()
    }
    
    private func collapseMenuBar() {
        guard self.isValidPosition && !self.isCollapsed else {
            autoCollapseIfNeeded()
            return
        }
        
        separateStatusBar.length = self.collapseSeparateStatusBarIconLength
        if let button = expandCollapseStatusBar.button {
            button.image = self.imgIconExpand
        }

    }
    
    private func expandMenubar() {
        guard self.isCollapsed else {return}
        separateStatusBar.length = normalSeparateStatusBarIconLength
        if let button = expandCollapseStatusBar.button {
            button.image = self.imgIconCollapse
        }
        autoCollapseIfNeeded()
    }
    
    private func autoCollapseIfNeeded() {
        guard Preferences.isAutoHide else {return}
        guard !isCollapsed else { return }
        
        startTimerToAutoHide()
    }
    
    private func startTimerToAutoHide() {
        timer?.invalidate()
        self.timer = Timer.scheduledTimer(withTimeInterval: Preferences.numberOfSecondForAutoHide, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                if Preferences.isAutoHide {
                    self?.collapseMenuBar()
                }
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
    
    private func updateMenuTitles() {
        guard let toggleAutoHideItem = separateStatusBar.menu?.item(withTag: 1) else { return }
        if Preferences.isAutoHide {
            toggleAutoHideItem.title = "Disable Auto Collapse".localized
        } else {
            toggleAutoHideItem.title = "Enable Auto Collapse".localized
        }
    }
    
    @objc func updateAutoHide() {
        updateMenuTitles()
        autoCollapseIfNeeded()
    }
    
    @objc func openPreferenceViewControllerIfNeeded() {
        Util.showPrefWindow()
    }
    
    @objc func toggleAutoHide() {
        Preferences.isAutoHide.toggle()
    }
}
