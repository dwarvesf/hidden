//
//  StatusBarController.swift
//  vanillaClone
//
//  Created by Thanh Nguyen on 1/30/19.
//  Copyright © 2019 Thanh Nguyen. All rights reserved.
//

import Cocoa
import AppKit
import ServiceManagement

class StatusBarController{
    
    //MARK: - Variables
    private var isToggle = true
    private let numberOfSecondForAutoHiden: Double = 5
    private var timer:Timer? = nil
    
    //MARK: - BarItems
    private let expandCollapseStatusBar = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
    private let seprateStatusBar = NSStatusBar.system.statusItem(withLength:10)
    private var appMenu:NSMenu? = nil
    
    
    func initView(){
        
        
        if let button = seprateStatusBar.button {
            button.image = NSImage(named:NSImage.Name("ic_line"))
        }
        
        appMenu = setupMenuUI()
        seprateStatusBar.menu = appMenu
        
        if let button = expandCollapseStatusBar.button {
                        button.image = NSImage(named:NSImage.Name("ic_collapse"))
                        button.target = self
                        button.action = #selector(expandCollapseIfNeeded(_:))
        }
        

        if Util.getShowPreferences() {
            openPreferenceViewControllerIfNeeded()
        }

       collapseBarWhenReopenAppIfNeeded()
    }
    
    private func collapseBarWhenReopenAppIfNeeded() {
        
        if(Util.getIsCollapse() && Util.getKeepLastState() && self.isToggle && self.isValidPosition())
        {
            setupCollapseMenuBar()
        }
    }
    
    private func isValidPosition() -> Bool {
        return Float((expandCollapseStatusBar.button?.getOrigin!.x)!) > Float((seprateStatusBar.button?.getOrigin!.x)!)
    }
    
    @objc func expandCollapseIfNeeded(_ sender: NSStatusBarButton) {
        if(isValidPosition())
        {
            if isToggle == false {
                expandMenubar()
            }else {
                setupCollapseMenuBar()
            }
        }
    }
    
    private func expandMenubar()
    {
        Util.setIsCollapse(false)
        seprateStatusBar.length = 10
        isToggle = !isToggle
        if let button = expandCollapseStatusBar.button {
            button.image = NSImage(named:NSImage.Name("ic_collapse"))
        }
        autoCollapseIfNeeded()
    }
    
    private func autoCollapseIfNeeded() {
        let isExpanded = Util.getIsCollapse()
        let isAutoHide = Util.getIsAutoHide()

        if isExpanded == false || isAutoHide == false {return}
        
        startTimerToAutoHide()
    }
    
    private func startTimerToAutoHide() {
        
        timer?.invalidate()
        
        timer = Timer.scheduledTimer(withTimeInterval: numberOfSecondForAutoHiden, repeats: false) { [weak self] (timer) in
            guard let strongSelf = self else{return}
            if(strongSelf.isToggle && strongSelf.isValidPosition())
            {
                strongSelf.setupCollapseMenuBar()
            }
        }
        
    }
    
    private func setupCollapseMenuBar() {
        Util.setIsCollapse(true)
        seprateStatusBar.length = 10000
        isToggle = !isToggle
        if let button = expandCollapseStatusBar.button {
            button.image = NSImage(named:NSImage.Name("ic_expand"))
        }
    }
    
    private func setupMenuUI() -> NSMenu {
        let menu = NSMenu()
        
        menu.addItem(NSMenuItem(title: "Preferences...", action: #selector(openPreferenceViewControllerIfNeeded), keyEquivalent: "P"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        menu.item(withTitle: "Preferences...")?.target = self
        
        return menu
    }
    
    @objc func openPreferenceViewControllerIfNeeded() {
        Util.showPrefWindow()
    }
}
