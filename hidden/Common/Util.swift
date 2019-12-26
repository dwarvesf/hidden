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
    static var isShowingPreferenceWindow = false
    static var numberOfSecondForAutoHide: Double {
        get {
            let numberOfSeconds = UserDefaults.standard.double(forKey: UserDefaults.Key.numberOfSecondForAutoHide)
            
            //For very first time, set it equal 10
            if numberOfSeconds == 0.0 {
                let defaultValue = 10.0
                UserDefaults.standard.set(defaultValue, forKey: UserDefaults.Key.numberOfSecondForAutoHide)
                return defaultValue
            }
            
            return numberOfSeconds
        }
        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.numberOfSecondForAutoHide)
        }
    }
    
    static func setUpAutoStart(isAutoStart:Bool) {
        let launcherAppId = "com.dwarvesv.LauncherApplication"
        let runningApps = NSWorkspace.shared.runningApplications
        let isRunning = !runningApps.filter { $0.bundleIdentifier == launcherAppId }.isEmpty
        
        SMLoginItemSetEnabled(launcherAppId as CFString, isAutoStart)
        
        if isRunning {
            DistributedNotificationCenter.default().post(name: Notification.Name("killLauncher"),
                                                         object: Bundle.main.bundleIdentifier!)
        }
    }
    
    static var isAutoStart : Bool {
        get {
            let savedValue = UserDefaults.standard.bool(forKey: UserDefaults.Key.isAutoStart)
            return savedValue
        }
        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.isAutoStart)
        }
    }
    
    static var isCollapse : Bool {
        get {
            let savedValue = UserDefaults.standard.bool(forKey: UserDefaults.Key.isCollapse)
            return savedValue
        }
        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.isCollapse)
        }
    }
    
    static var isAutoHide : Bool {
        get {
            let savedValue = UserDefaults.standard.bool(forKey: UserDefaults.Key.isAutoHide)
            return savedValue
        }
        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.isAutoHide)
        }
    }
    
    static var isKeepInDock : Bool {
        get {
            let savedValue = UserDefaults.standard.bool(forKey: UserDefaults.Key.isKeepInDock)
            return savedValue
        }
        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.isKeepInDock)
        }
    }
    
    static var isShowPreferences : Bool {
        get {
            let savedValue = UserDefaults.standard.bool(forKey: UserDefaults.Key.isShowPreferences)
            return savedValue
        }
        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.isShowPreferences)
        }
    }
    
    static var keepLastState : Bool {
        get {
            let savedValue = UserDefaults.standard.bool(forKey: UserDefaults.Key.isKeepLastState)
            return savedValue
        }
        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.isKeepLastState)
        }
    }
    
    static var isGhostModeEnabled : Bool {
        get {
            let savedValue = UserDefaults.standard.bool(forKey: UserDefaults.Key.isPermHideEnabled)
            return savedValue
        }
        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.isPermHideEnabled)
        }
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
    
    static func getAndShowPrefWindow() -> NSWindow {
        Util.isShowPreferences = true
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
    
    static func toggleGhostMode() {
        let delegate = NSApplication.shared.delegate as! AppDelegate
        let statusBarController = delegate.statusBarController
        statusBarController.showGhostButtonIfNeeded()
    }
}

extension Bool {
    func toStateValue() -> NSControl.StateValue {
        return self ? NSControl.StateValue.on : NSControl.StateValue.off
    }
}

extension NSControl.StateValue {
    func toBool() -> Bool {
        return self == .on ? true : false
    }
}
