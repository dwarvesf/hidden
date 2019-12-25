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
    
    static var isAutoStart : Bool {
        get {
            let savedValue = UserDefaults.standard.bool(forKey: IS_AUTO_START)
            return savedValue
        }
        set {
            UserDefaults.standard.set(newValue, forKey: IS_AUTO_START)
        }
    }
    
    static var isCollapse : Bool {
        get {
            let savedValue = UserDefaults.standard.bool(forKey: IS_COLLAPSE)
            return savedValue
        }
        set {
            UserDefaults.standard.set(newValue, forKey: IS_COLLAPSE)
        }
    }
    
    static var isAutoHide : Bool {
        get {
            let savedValue = UserDefaults.standard.bool(forKey: IS_AUTO_HIDE)
            return savedValue
        }
        set {
            UserDefaults.standard.set(newValue, forKey: IS_AUTO_HIDE)
        }
    }
    
    static var isKeepInDock : Bool {
        get {
            let savedValue = UserDefaults.standard.bool(forKey: IS_KEEP_IN_DOCK)
            return savedValue
        }
        set {
            UserDefaults.standard.set(newValue, forKey: IS_KEEP_IN_DOCK)
        }
    }
    
    static var showPreferences : Bool {
        get {
            let savedValue = UserDefaults.standard.bool(forKey: IS_SHOW_PREFERENCES)
            return savedValue
        }
        set {
            UserDefaults.standard.set(newValue, forKey: IS_SHOW_PREFERENCES)
        }
    }
    
    static var keepLastState : Bool {
        get {
            let savedValue = UserDefaults.standard.bool(forKey: IS_KEEP_LAST_STATE)
            return savedValue
        }
        set {
            UserDefaults.standard.set(newValue, forKey: IS_KEEP_LAST_STATE)
        }
    }
    
    static var isPermHideEnabled : Bool {
        get {
            let savedValue = UserDefaults.standard.bool(forKey: Notification.Name.IS_PERM_HIDE_ENABLED)
            return savedValue
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Notification.Name.IS_PERM_HIDE_ENABLED)
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
    
    static func permHideChanged() {
        let delegate = NSApplication.shared.delegate as! AppDelegate
        let statusBarController = delegate.statusBarController
        statusBarController.setPermHideEnabled(self.isPermHideEnabled)
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
