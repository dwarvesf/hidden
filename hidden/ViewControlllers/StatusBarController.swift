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
    
    var isToggle = true
    
    let expandCollapseStatusBar = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
    let seprateStatusBar = NSStatusBar.system.statusItem(withLength:10)
    var btnDot: NSStatusBarButton? = nil
    var appMenu:NSMenu? = nil
    var timer:Timer? = nil
    
    func initView(){
        
        appMenu = setupMenuUI()
        
        if let button = seprateStatusBar.button {
            button.image = NSImage(named:NSImage.Name("ic_line"))
        }
        
        if let button = expandCollapseStatusBar.button {
                        button.image = NSImage(named:NSImage.Name("ic_collapse"))
                        btnDot = NSStatusBarButton.collapseBarButtonItem()
                        btnDot?.target = self
                        btnDot?.action = #selector(statusBarButtonClicked(_:))
                        button.addSubview(btnDot!)
        }
        

        if Util.getShowPreferences() {
            openPreferenceViewControllerIfNeeded(nil)
        }

       checkCollapseWhenOpen()
    }
    
    private func checkCollapseWhenOpen(){
        if(Util.getIsCollapse())
        {
            if(isToggle && isValidPosition())
            {
                setupCollapseMenuBar()
            }
        }
    }
    
    func isValidPosition() -> Bool {
        return Float((expandCollapseStatusBar.button?.getOrigin!.x)!) > Float((seprateStatusBar.button?.getOrigin!.x)!)
    }
    
    @objc func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent!
        
        if event.type == NSEvent.EventType.rightMouseUp {
            openAppMenu()
        } else {
            expandCollapseIfNeeded()
        }
    }
    
    private func openAppMenu()
    {
        if (appMenu != nil)
        {
            expandCollapseStatusBar.menu = appMenu //set the menu
            
            let p = NSPoint(x: 0,
                            y: (expandCollapseStatusBar.statusBar?.thickness)!)
            self.appMenu!.popUp(positioning: self.appMenu!.item(at: 0), at:p , in: btnDot)
            
        }
    }
    
    @objc func expandCollapseIfNeeded() {
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
        if(Util.getIsAutoHide())
        {
            startTimerToAutoHide()
        }
    }
    
    private func startTimerToAutoHide(){
        
        timer?.invalidate()
        
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] (timer) in
            guard let strongSelf = self else{return}
            if(strongSelf.isToggle && strongSelf.isValidPosition())
            {
                strongSelf.setupCollapseMenuBar()
            }
        }
        
    }
    
    private func setupCollapseMenuBar(){
        Util.setIsCollapse(true)
        seprateStatusBar.length = 10000
        isToggle = !isToggle
        if let button = expandCollapseStatusBar.button {
            button.image = NSImage(named:NSImage.Name("ic_expand"))
        }
        
    }
    
    private func setupMenuUI()-> NSMenu {
        let menu = NSMenu()
        
        menu.addItem(NSMenuItem(title: "Preferences...", action: #selector(openPreferenceViewControllerIfNeeded(_:)), keyEquivalent: "P"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        menu.item(withTitle: "Preferences...")?.target = self
        
        return menu
    }
    
    @objc func openPreferenceViewControllerIfNeeded(_ sender: Any?) {
        Util.showPrefWindow()
    }
}
