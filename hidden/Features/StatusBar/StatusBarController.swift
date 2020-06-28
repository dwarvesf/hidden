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
    private let separateStatusBar = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    
    private let normalStatusBarIconLength: CGFloat = 20
    private let collapseStatusBarIconLength: CGFloat = 10000
    
    private let imgIconLine = NSImage(named:NSImage.Name("ic_line"))
    private let imgIconCollapse = NSImage(named:NSImage.Name("ic_collapse"))
    private let imgIconExpand = NSImage(named:NSImage.Name("ic_expand"))
    
    private var isCollapsed: Bool {
        return self.separateStatusBar.length == self.collapseStatusBarIconLength
    }
    
    private var isValidPosition: Bool {
        guard
            let expandBarButtonX = self.expandCollapseStatusBar.button?.getOrigin?.x,
            let separateBarButtonX = self.separateStatusBar.button?.getOrigin?.x
            else {return false}
        
        return expandBarButtonX > separateBarButtonX
    }
    
    //MARK: - Methods
    init() {
        
        setupUI()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: {
            self.collapseMenuBar()
        })
        
        autoCollapseIfNeeded()
    }
    
    private func setupUI() {
        if let button = separateStatusBar.button {
            button.image = self.imgIconLine
        }
        
        separateStatusBar.menu = self.getContextMenu()
        
        if let button = expandCollapseStatusBar.button {
            button.image = self.imgIconCollapse
            button.target = self
            button.action = #selector(expandCollapseIfNeeded(_:))
        }
        
        expandCollapseStatusBar.autosaveName = "hiddenbar_expandcollapse";
        separateStatusBar.autosaveName = "hiddenbar_separate";
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
    
    private func getContextMenu() -> NSMenu {
        let menu = NSMenu()
        
        let prefItem = NSMenuItem(title: "Preferences...".localized, action: #selector(openPreferenceViewControllerIfNeeded), keyEquivalent: "P")
        prefItem.target = self
        menu.addItem(prefItem)
        
        let toggleAutoHideItem = NSMenuItem(title: "Toggle Auto Collapse".localized, action: #selector(toggleAutoHide), keyEquivalent: "t")
        toggleAutoHideItem.target = self
        toggleAutoHideItem.tag = 1
        NotificationCenter.default.addObserver(self, selector: #selector(updateMenuTitles), name: .prefsChanged, object: nil)
        menu.addItem(toggleAutoHideItem)
        
        updateMenuTitles()

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit".localized, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        
        return menu
    }
    
    @objc func updateMenuTitles() {
        guard let toggleAutoHideItem = separateStatusBar.menu?.item(withTag: 1) else { return }
        if Preferences.isAutoHide {
            toggleAutoHideItem.title = "Disable Auto Collapse".localized
        } else {
            toggleAutoHideItem.title = "Enable Auto Collapse".localized
        }
    }
    
    @objc func openPreferenceViewControllerIfNeeded() {
        Util.showPrefWindow()
    }
    
    @objc func toggleAutoHide() {
        Preferences.isAutoHide.toggle()
    }
}
