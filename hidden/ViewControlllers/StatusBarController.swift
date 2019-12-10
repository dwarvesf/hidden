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
            openPreferenceViewControllerIfNeeded(nil)
        }

       checkCollapseWhenOpen()
    }
    
    private func checkCollapseWhenOpen(){
        if(Util.getIsCollapse() && Util.getKeepLastState())
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
