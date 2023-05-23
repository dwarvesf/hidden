//
//  AppDelegate.swift
//  vanillaClone
//
//  Created by Thanh Nguyen on 1/24/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import AppKit
import HotKey

class AppDelegate: NSObject, NSApplicationDelegate{
    
    //var statusBarController = StatusBarController()

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSLog("App launched.")
        //ServiceManager.setup() //using LaunchAtLogin package
        StatusBarController.setup()
        HotKeyManager.setupHotKey()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        NSLog("App shutting down.")
    }
   
}

 
