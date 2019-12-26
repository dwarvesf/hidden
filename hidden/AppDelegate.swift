//
//  AppDelegate.swift
//  vanillaClone
//
//  Created by Thanh Nguyen on 1/24/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import Cocoa
import AppKit
import ServiceManagement
import HotKey

@NSApplicationMain

class AppDelegate: NSObject, NSApplicationDelegate{
    
    var statusBarController = StatusBarController()
    
    var hotKey: HotKey? {
        didSet {
            guard let hotKey = hotKey else { return }
            
            hotKey.keyDownHandler = { [weak self] in
                self?.statusBarController.expandCollapseIfNeeded(nil)
            }
        }
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        Util.setUpAutoStart(isAutoStart: Util.isAutoStart)
        statusBarController.initView()
        setupHotKey()
    }
    
    func setupHotKey() {
        guard let globalKey = Preferences.GlobalKey else {return}
        hotKey = HotKey(keyCombo: KeyCombo(carbonKeyCode: globalKey.keyCode, carbonModifiers: globalKey.carbonFlags))
    }
    
    func applicationWillBecomeActive(_ notification: Notification) {
        let _ = Util.toggleDockIcon(Util.isKeepInDock)
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Handle open preferences window
        Util.getAndShowPrefWindow()
        
        return true
    }
    
   
}
