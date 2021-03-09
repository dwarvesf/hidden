//
//  Util.swift
//  vanillaClone
//
//  Created by Thanh Nguyen on 1/29/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import AppKit
import Foundation
import ServiceManagement


class Util {
    
    static func setUpAutoStart(isAutoStart:Bool) {
        let runningApps = NSWorkspace.shared.runningApplications
        let isRunning = !runningApps.filter { $0.bundleIdentifier == Constant.launcherAppId }.isEmpty
        
        SMLoginItemSetEnabled(Constant.launcherAppId as CFString, isAutoStart)
        
        if isRunning {
            DistributedNotificationCenter.default().post(name: Notification.Name("killLauncher"),
                                                         object: Bundle.main.bundleIdentifier!)
        }
    }
    
    static func showPrefWindow() {
        let prefWindow = PreferencesWindowController.shared.window
        prefWindow?.bringToFront()
    }
    
    static var menuBarIsInUse : Bool {
        for info in WindowInfo.openedWindows {
            if info.layer > 100 && info.layer < 110 {
                return true
            }
        }
        return false
    }
   
}
