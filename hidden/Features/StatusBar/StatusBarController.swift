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
    private var permHideStatusBar : NSStatusItem? = nil
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
        
        setUpPermHideStatusBarIfNeeded()
        
        self.exitEditPermHide()
        
        if Util.showPreferences {
            openPreferenceViewControllerIfNeeded()
        }
        
        collapseBarWhenReopenAppIfNeeded()
        autoCollapseIfNeeded()
    }
    
    private func setUpPermHideStatusBarIfNeeded() {
        if Util.isPermHideEnabled {
            permHideStatusBar = NSStatusBar.system.statusItem(withLength: 20)
            if let button = permHideStatusBar?.button {
                button.image = NSImage(named: NSImage.Name("ic_dot"))
            }
        }
    }
    
    private func collapseBarWhenReopenAppIfNeeded() {
        
        if(Util.isCollapse && Util.keepLastState && self.isValidPosition())
        {
            setupCollapseMenuBar()
        }
    }
    
    private func isValidPosition() -> Bool {
        return Float((expandCollapseStatusBar.button?.getOrigin!.x)!) > Float((seprateStatusBar.button?.getOrigin!.x)!)
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
    
    private func expandMenubar()
    {
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
        Util.isCollapse = true
        seprateStatusBar.length = 10000
        if let button = expandCollapseStatusBar.button {
            button.image = NSImage(named:NSImage.Name("ic_expand"))
        }
    }
    
    private func editPermHide() {
        permHideStatusBar?.length = 20
    }
    
    private func exitEditPermHide() {
        
        var permHideIsOnLeftOfSeperator : Bool {
            let dotX = Float((permHideStatusBar?.button?.getOrigin?.x)!)
            let lineX = Float((seprateStatusBar.button?.getOrigin?.x)!)
            return dotX < lineX
        }
        
        if Util.isPermHideEnabled && permHideIsOnLeftOfSeperator {
            permHideStatusBar?.length = 10000
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
        let window = Util.showPrefWindow() as! PreferencesWindow
        editPermHide()
        window.windowClosedHandler {
            self.exitEditPermHide()
        }
    }
    
    func setPermHideEnabled(_ permHideEnabled: Bool) {
        if permHideEnabled {
            permHideStatusBar?.length = 20
        } else {
            permHideStatusBar?.length = 0
        }
    }
}
