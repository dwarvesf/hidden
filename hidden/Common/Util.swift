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
    
    class SharedValues {
        static var isUsingLTRLanguage = false

        static var statusbarHeight : CGFloat = .nan
        
        static var screenHeight : CGFloat = .nan
        static var screenWidth  : CGFloat = .nan
    }
    
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
    
    static var screenWithMouse : NSScreen? {
      let mouseLocation = NSEvent.mouseLocation
      let screens = NSScreen.screens
      let screenWithMouse = (screens.first { NSMouseInRect(mouseLocation, $0.frame, false) })
      return screenWithMouse
    }
    
    static var menubarIsInUse : Bool {
        guard let infoList = WindowInfo.infoList else { return false }
        for windowInfo in infoList {
            // For some reason, menu windows always has kCGWindowLayer = 101
            // To avoid falsely identifying, the app also checks if:
            // - the window's top edge is next to the status bar bottom edge
            // - the window doesn't stick to any edges of the screen
            // - the window has kCGWindowLayer > 100 and kCGWindowLayer < 150
            
            guard let windowLayer = windowInfo[WindowInfo.InfoType.layer.rawValue] as? Int,
                  windowLayer == 101,
                  let bounds = windowInfo[WindowInfo.InfoType.bounds.rawValue],
                  let cgRect = CGRect(dictionaryRepresentation: bounds as! CFDictionary) else { continue }
            
            if  cgRect.minY == Util.SharedValues.statusbarHeight + 1 &&
                        // "+1" because the frame of the window should be *NEXT TO the status bar not equal
                cgRect.minX != 0 &&
                cgRect.maxX != Util.SharedValues.screenWidth &&
                cgRect.maxY != Util.SharedValues.screenHeight {
                return true
            }
        }
        return false
    }
   
}
