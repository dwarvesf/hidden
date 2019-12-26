//
//  StatusBarController.swift
//  vanillaClone
//
//  Created by Thanh Nguyen on 1/30/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import Cocoa
import AppKit
import ServiceManagement

class StatusBarController{
    
    //MARK: - Variables
    private var timer:Timer? = nil
    
    //MARK: - BarItems
    private let expandCollapseStatusBar = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
    private let seprateStatusBar = NSStatusBar.system.statusItem(withLength:20)
    private var btnGhost = NSStatusBar.system.statusItem(withLength: 0)
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
        
        setUpGhostBarStatusItem()
        
        self.enableGhostModeIfNeeded()
        
        if Util.isShowPreferences {
            openPreferenceViewControllerIfNeeded()
        }
        
        collapseBarWhenReopenAppIfNeeded()
        autoCollapseIfNeeded()
    }
    
    private func setUpGhostBarStatusItem() {
       if let button = btnGhost.button {
        button.title = "👻"
       }
    }
    
    private func collapseBarWhenReopenAppIfNeeded() {
        
        if(Util.isCollapse && Util.keepLastState && self.isValidPosition())
        {
            setupCollapseMenuBar()
        }
    }
    
    private func isValidPosition() -> Bool {
        return Float((expandCollapseStatusBar.button?.position!.x)!) > Float((seprateStatusBar.button?.position!.x)!)
    }
    
    @objc func expandCollapseIfNeeded(_ sender: NSStatusBarButton?) {
        if(isValidPosition())
        {
            if seprateStatusBar.length != 20.0 {
                expandMenubar()
            }else {
                setupCollapseMenuBar()
            }
        }
    }
    
    private func expandMenubar() {
        Util.isCollapse = false
        seprateStatusBar.length = 20
        if let button = expandCollapseStatusBar.button {
            button.image = NSImage(named:NSImage.Name("ic_collapse"))
        }
        autoCollapseIfNeeded()
    }
    
    private func autoCollapseIfNeeded() {
        if Util.isAutoHide == false {return}
        
        startTimerToAutoHide()
    }
    
    private func startTimerToAutoHide() {
        DispatchQueue.main.async {
            self.timer?.invalidate()
            
            self.timer = Timer.scheduledTimer(withTimeInterval: Util.numberOfSecondForAutoHide, repeats: false) { [weak self] (timer) in
                guard let strongSelf = self else{return}
                if strongSelf.isValidPosition()
                {
                    strongSelf.setupCollapseMenuBar()
                }
            }
        }
    }
    
    private func setupCollapseMenuBar() {
        if Util.isShowPreferences {return}

        Util.isCollapse = true
        seprateStatusBar.length = 10000
        if let button = expandCollapseStatusBar.button {
            button.image = NSImage(named:NSImage.Name("ic_expand"))
        }
    }
    

    
    private func enableGhostModeIfNeeded() {
        var permHideIsOnLeftOfSeperator : Bool {
            let dotX = Float((btnGhost.button?.position?.x)!)
            let lineX = Float((seprateStatusBar.button?.position?.x)!)
            return dotX < lineX
        }
        
        if Util.isGhostModeEnabled && permHideIsOnLeftOfSeperator {
            btnGhost.length = 10000
        }else {
            btnGhost.length = 0
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
        let window = Util.getAndShowPrefWindow() as! PreferencesWindow
        showGhostButtonIfNeeded()
        window.windowClosedHandler { [weak self] in
            Util.isShowPreferences = false
            self?.enableGhostModeIfNeeded()
            self?.autoCollapseIfNeeded()
        }
    }
    func showGhostButtonIfNeeded() {
        let btnGhostLength: CGFloat = Util.isGhostModeEnabled ? 22 : 0
        btnGhost.length = btnGhostLength
    }
}
