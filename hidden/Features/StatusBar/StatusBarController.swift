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
    
    private var btnHiddenLength: CGFloat =  20
    private let btnHiddenCollapseLength: CGFloat = 10000
    
    private let btnAlwaysHiddenLength: CGFloat = Preferences.alwaysHiddenSectionEnabled ? 20 : 0
    private let btnAlwaysHiddenEnableExpandCollapseLength: CGFloat = Preferences.alwaysHiddenSectionEnabled ? 10000 : 0
    
    private let imgIconLine = NSImage(named:NSImage.Name("ic_line"))
    
    private var isCollapsed: Bool {
        return self.btnSeparate.length == self.btnHiddenCollapseLength
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
    
    //MARK: - Methods
    init() {
        
        setupUI()
        setupAlwayHideStatusBar()
        setupTransparentExpandIcon()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: {
            self.collapseMenuBar()
        })
        
        if Preferences.areSeparatorsHidden {hideSeparators()}
        autoCollapseIfNeeded()
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
            } else {
                self.showHideSeparatorsAndAlwayHideArea()
            }
        }
    }
    
    func showHideSeparatorsAndAlwayHideArea() {
        Preferences.areSeparatorsHidden ? self.showSeparators() : self.hideSeparators()
        
        if self.isCollapsed {self.expandMenubar()}
    }
    
    private func showSeparators() {
        Preferences.areSeparatorsHidden = false
        
        if !self.isCollapsed {
            self.btnSeparate.length = self.btnHiddenLength
        }
        self.btnAlwaysHidden?.length = self.btnAlwaysHiddenLength
    }
    
    private func hideSeparators() {
        guard self.isBtnAlwaysHiddenValidPosition else {return}
        
        Preferences.areSeparatorsHidden = true
        
        if !self.isCollapsed {
            self.btnSeparate.length = self.btnHiddenLength
        }
        self.btnAlwaysHidden?.length = self.btnAlwaysHiddenEnableExpandCollapseLength
    }
    
    func expandCollapseIfNeeded() {
        //prevented rapid click cause icon show many in Dock
        if isToggle {return}
        isToggle = true
        self.isCollapsed ? self.expandMenubar() : self.collapseMenuBar()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.isToggle = false
        }
    }
    
    private func collapseMenuBar() {
        guard self.isBtnSeparateValidPosition && !self.isCollapsed else {
            autoCollapseIfNeeded()
            return
        }
        
        btnSeparate.length = self.btnHiddenCollapseLength
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
        btnSeparate.length = btnHiddenLength
        if let button = btnExpandCollapse.button {
            button.image = Assets.collapseImage
        }
        autoCollapseIfNeeded()
        
        if Preferences.useFullStatusBarOnExpandEnabled {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            
        }
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
        if Preferences.alwaysHiddenSectionEnabled {
            self.btnAlwaysHidden =  NSStatusBar.system.statusItem(withLength: 20)
            if let button = btnAlwaysHidden?.button {
                button.image = self.imgIconLine
                button.appearsDisabled = true
            }
            self.btnAlwaysHidden?.autosaveName = "hiddenbar_terminate";
            
        }else {
            self.btnAlwaysHidden = nil
        }
    }
    
    private func setupTransparentExpandIcon() {
        NotificationCenter.default.addObserver(self, selector: #selector(toggleTransparentExpandIconIfNeeded), name: .transparentExpandIconToggle, object: nil)
    }
    @objc private func toggleTransparentExpandIconIfNeeded() {
        guard self.isCollapsed else { return }
        if let button = btnExpandCollapse.button {
            button.image = Assets.expandImage
        }
    }
}
