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
    private var mouseOverDetector : MouseOverDetector?
    
    //MARK: - BarItems
        
    private let expandCollapseStatusBar = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let separateStatusBar = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var alwayHideSeparateStatusBar:NSStatusItem? = nil
    
    private var normalSeparateStatusBarIconLength: CGFloat { return Preferences.areSeparatorsHidden ? 0 : 20 }
    private let collapseSeparateStatusBarIconLength: CGFloat = 10000
    
    private let normalTerminateStatusBarIconLength: CGFloat = Preferences.alwaysHiddenSectionEnabled ? 20 : 0
    private let collapseTerminateStatusBarIconLength: CGFloat = Preferences.alwaysHiddenSectionEnabled ? 10000 : 0
    
    private let imgIconLine = NSImage(named:NSImage.Name("ic_line"))
    
    private var isCollapsed: Bool {
        return self.separateStatusBar.length == self.collapseSeparateStatusBarIconLength
    }
    
    private var isValidPosition: Bool {
        guard
            let expandBarButtonX = self.expandCollapseStatusBar.button?.getOrigin?.x,
            let separateBarButtonX = self.separateStatusBar.button?.getOrigin?.x
            else {return false}
        
        if Constant.isUsingLTRLanguage {
            return expandBarButtonX >= separateBarButtonX
        } else {
            return expandBarButtonX <= separateBarButtonX
        }
    }
    private var isValidTogglablePosition: Bool {
        if !Preferences.alwaysHiddenSectionEnabled { return true }
        
        guard
            let separateBarButtonX = self.separateStatusBar.button?.getOrigin?.x,
            let terminateBarButtonX = self.alwayHideSeparateStatusBar?.button?.getOrigin?.x
            else {return false}
        
        if Constant.isUsingLTRLanguage {
            return separateBarButtonX >= terminateBarButtonX
        } else {
            return separateBarButtonX <= terminateBarButtonX
        }
    }
    
    //MARK: - Methods
    init() {
        
        setupUI()
        setupAlwayHideStatusBar()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: {
            self.collapseMenuBar()
        })
        
        if Preferences.areSeparatorsHidden {hideSeparators()}
        autoCollapseIfNeeded()
        
        mouseOverDetector = MouseOverDetector(
            entersArea: expandMenubar,
            leavesArea: { if !$0 {self.collapseMenuBar()} }
        )
        
        updatePrefs()
    }
    
    private func setupUI() {
        if let button = separateStatusBar.button {
            button.image = self.imgIconLine
        }
        let menu = self.getContextMenu()
        separateStatusBar.menu = menu

        updateAutoCollapseMenuTitle()
        
        if let button = expandCollapseStatusBar.button {
            button.image = Assets.collapseImage
            button.target = self
            
            button.action = #selector(self.expandCollapseButtonPressed(sender:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        expandCollapseStatusBar.autosaveName = "hiddenbar_expandcollapse";
        separateStatusBar.autosaveName = "hiddenbar_separate";
    }
    
    @objc func expandCollapseButtonPressed(sender: NSStatusBarButton) {
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
            self.separateStatusBar.length = self.normalSeparateStatusBarIconLength
        }
        self.alwayHideSeparateStatusBar?.length = self.normalTerminateStatusBarIconLength
    }
    
    private func hideSeparators() {
        guard self.isValidTogglablePosition else {return}
        
        Preferences.areSeparatorsHidden = true
        
        if !self.isCollapsed {
            self.separateStatusBar.length = self.normalSeparateStatusBarIconLength
        }
        self.alwayHideSeparateStatusBar?.length = self.collapseTerminateStatusBarIconLength
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
            button.image = Assets.expandImage
        }
        if Preferences.useFullStatusBarOnExpandEnabled {
            NSApp.setActivationPolicy(.accessory)
            NSApp.deactivate()
        }
    }
    
    private func expandMenubar() {
        guard self.isCollapsed else {return}
        separateStatusBar.length = normalSeparateStatusBarIconLength
        if let button = expandCollapseStatusBar.button {
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
        NotificationCenter.default.addObserver(self, selector: #selector(updatePrefs), name: .prefsChanged, object: nil)
        menu.addItem(toggleAutoHideItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit".localized, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        return menu
    }
    
    private func updateAutoCollapseMenuTitle() {
        guard let toggleAutoHideItem = separateStatusBar.menu?.item(withTag: 1) else { return }
        if Preferences.isAutoHide {
            toggleAutoHideItem.title = "Disable Auto Collapse".localized
        } else {
            toggleAutoHideItem.title = "Enable Auto Collapse".localized
        }
    }
    
    @objc func updatePrefs() {
        updateAutoCollapseMenuTitle()
        autoCollapseIfNeeded()
        
        if Preferences.autoExpandCollapse {
            mouseOverDetector?.stop()
            mouseOverDetector?.start()
        } else {
            mouseOverDetector?.stop()
        }
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
            self.alwayHideSeparateStatusBar =  NSStatusBar.system.statusItem(withLength: 20)
            if let button = alwayHideSeparateStatusBar?.button {
                button.image = self.imgIconLine
                button.appearsDisabled = true
            }
            self.alwayHideSeparateStatusBar?.autosaveName = "hiddenbar_terminate";
            
        }else {
            self.alwayHideSeparateStatusBar = nil
        }
    }
}
