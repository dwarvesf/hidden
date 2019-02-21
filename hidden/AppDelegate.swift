//
//  AppDelegate.swift
//  vanillaClone
//
//  Created by Thanh Nguyen on 1/24/19.
//  Copyright © 2019 Thanh Nguyen. All rights reserved.
//

import Cocoa
import AppKit
import ServiceManagement

@NSApplicationMain

class AppDelegate: NSObject, NSApplicationDelegate{
    
    var statusBarController = StatusBarController()

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        
        Util.setUpAutoStart(isAutoStart: Util.getIsAutoStart())
        statusBarController.initView()
    }
    
    func applicationWillBecomeActive(_ notification: Notification) {
        let _ = Util.toggleDockIcon(Util.getIsKeepInDock())
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if(!Util.isMenuOpened())
        {
            Util.showPrefWindow()
        }
        
        Util.bringToFront(window: NSApp.mainWindow)
        return true
    }
    
   
}
