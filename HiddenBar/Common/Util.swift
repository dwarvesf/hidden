//
//  Util.swift
//  vanillaClone
//
//  Created by Thanh Nguyen on 1/29/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import AppKit
import Foundation
//import ServiceManagement



class Util {
    
    static func showPrefWindow() {
        let prefWindow = PreferencesWindowController.shared.window
        prefWindow?.bringToFront()
    }
    
    static func hasFullScreenWindow() -> Bool
    {
        // TODO: A better method detecting active full screen windows to prevent glitching
        let previousPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.accessory)
        guard let windows = CGWindowListCopyWindowInfo(CGWindowListOption(rawValue: CGWindowListOption.optionOnScreenOnly.rawValue | CGWindowListOption.excludeDesktopElements.rawValue), kCGNullWindowID) else {
            return false
        }
        
        guard let screenFrame = NSScreen.main?.frame else {
            return false
        }

        for window in windows as NSArray
        {
            guard let winInfo = window as? NSDictionary, let frameInfo = winInfo["kCGWindowBounds"] as? NSDictionary else { continue }
            
            if frameInfo["Height"] as? CGFloat == screenFrame.height, frameInfo["Width"] as? CGFloat == screenFrame.width,
               frameInfo["X"] as? CGFloat == 0, frameInfo["Y"] as? CGFloat == 0,
               winInfo["kCGWindowOwnerName"] as? String != "Dock"
            {
#if DEBUG
                NSLog("Found full screen window: \(winInfo)")
#endif
                return true
            }
        }
        NSApp.setActivationPolicy(previousPolicy)
        //NSLog("No full screen window found.")
        return false
    }
}
