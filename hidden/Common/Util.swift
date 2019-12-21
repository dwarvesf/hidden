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
    
    static var numberOfSecondForAutoHide: Double {
        get {
            let numberOfSeconds = UserDefaults.standard.double(forKey: Notification.Name.numberOfSecondForAutoHide)
            
            //For very first time, set it equal 10
            if numberOfSeconds == 0.0 {
                let defaultValue = 10.0
                UserDefaults.standard.set(defaultValue, forKey: Notification.Name.numberOfSecondForAutoHide)
                return defaultValue
            }
            
            return numberOfSeconds
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Notification.Name.numberOfSecondForAutoHide)
        }
    }
    
    static func setUpAutoStart(isAutoStart:Bool)
    {
        let launcherAppId = "com.dwarvesv.LauncherApplication"
        let runningApps = NSWorkspace.shared.runningApplications
        let isRunning = !runningApps.filter { $0.bundleIdentifier == launcherAppId }.isEmpty
        
        SMLoginItemSetEnabled(launcherAppId as CFString, isAutoStart)
        
        if isRunning {
            DistributedNotificationCenter.default().post(name: Notification.Name("killLauncher"),
                                                         object: Bundle.main.bundleIdentifier!)
        }
    }
    
    static func setIsAutoStart(_ isAutoStart:Bool){
        UserDefaults.standard.set(isAutoStart, forKey: IS_AUTO_START)
        
    }
    
    static func getIsCollapse() -> Bool{
        let savedValue = UserDefaults.standard.bool(forKey: IS_COLLAPSE)
        return savedValue
    }
    
    static func setIsCollapse(_ isCollapse:Bool){
        UserDefaults.standard.set(isCollapse, forKey: IS_COLLAPSE)
        
    }
    
    static func getIsAutoStart() -> Bool{
        let savedValue = UserDefaults.standard.bool(forKey: IS_AUTO_START)
        return savedValue
    }
    
    
    
    static func getStateAutoStart() -> NSControl.StateValue{
        if(getIsAutoStart())
        {
            return .on
        }
        return .off
    }
    
    static func setIsAutoHide(_ isAutoHide:Bool){
        UserDefaults.standard.set(isAutoHide, forKey: IS_AUTO_HIDE)
        
    }
    
    static func getIsAutoHide()->Bool{
        let isAutoHide = UserDefaults.standard.bool(forKey: IS_AUTO_HIDE)
        return isAutoHide
    }
    
    static func getStateAutoHide() -> NSControl.StateValue{
        if(getIsAutoHide())
        {
            return .on
        }
        return .off
    }
    
    static func setIsKeepInDock(_ isKeepInDock:Bool){
        UserDefaults.standard.set(isKeepInDock, forKey: IS_KEEP_IN_DOCK)
        
    }
    
    static func getIsKeepInDock() -> Bool{
        UserDefaults.standard.register(defaults: [IS_KEEP_IN_DOCK : true])
        let savedValue = UserDefaults.standard.bool(forKey: IS_KEEP_IN_DOCK)
        return savedValue
    }
    
    static func getStateKeepInDock() -> NSControl.StateValue {
        if(getIsKeepInDock())
        {
            return .on
        }
        return .off
    }
    
    static func getShowPreferences() -> Bool {
        UserDefaults.standard.register(defaults: [IS_SHOW_PREFERENCES : true])
        return UserDefaults.standard.bool(forKey: IS_SHOW_PREFERENCES)
    }
    
    static func setShowPreferences(_ isShowPreferences: Bool) {
        UserDefaults.standard.set(isShowPreferences, forKey: IS_SHOW_PREFERENCES)
    }
    
    static func getStateShowPreferences() -> NSControl.StateValue {
        return getShowPreferences() ? .on : .off
    }
    
    
    static func getKeepLastState() -> Bool {
        let savedValue = UserDefaults.standard.bool(forKey: IS_KEEP_LAST_STATE)
        return savedValue
    }
    
    static func setKeepLastState(_ isKeepLastState: Bool) {
        UserDefaults.standard.set(isKeepLastState, forKey: IS_KEEP_LAST_STATE)
    }
    
    static func getStateKeepLastState() -> NSControl.StateValue {
        return getKeepLastState() ? .on : .off
    }
    
    
    static func isMenuOpened() -> Bool {
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
        let windowsListInfo = CGWindowListCopyWindowInfo(options, CGWindowID(0))
        let infoList = windowsListInfo as! [[String:Any]]
        let names = infoList.map { dict in
            return dict["kCGWindowOwnerName"] as? String
            }.filter({ (name) -> Bool in
                name == App_Name
            })
        return names.count >= 2
    }
    
    static func showPrefWindow() -> NSWindow {
        let prefWindow = PreferencesWindowController.shared.window!
        Util.bringToFront(window: prefWindow)
        return prefWindow
    }
    
    static func toggleDockIcon(_ state: Bool) -> Bool {
        var result: Bool
        if state {
            result = NSApp.setActivationPolicy(NSApplication.ActivationPolicy.regular)
        }
        else {
            result = NSApp.setActivationPolicy(NSApplication.ActivationPolicy.accessory)
        }
        return result
    }
    
    static func bringToFront(window:NSWindow?) {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
