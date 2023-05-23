//
//  UserDefault+Extension.swift
//  Hidden Bar
//
//  Created by phucld on 12/18/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import Foundation
import LaunchAtLogin


enum PreferenceKeys {
    static let globalKey = "globalKey"
    static let numberOfSecondForAutoHide = "numberOfSecondForAutoHide"
    //static let isAutoStart = "isAutoStart"
    static let isAutoHide = "isAutoHide"
    static let isShowPreference = "isShowPreferences"
    static let isUsingFullStatusBar = "isUsingFullStatusBar"
    static let isEditMode = "isEditMode"
    static let statusBarPolicy = "statusBarPolicy"
}

enum Preferences {
    
    static func setDefault() -> Void {
        UserDefaults.standard.register(defaults: [
           //PreferenceKeys.isAutoStart: false,
           PreferenceKeys.isShowPreference: true,
           PreferenceKeys.isAutoHide: true,
           PreferenceKeys.numberOfSecondForAutoHide: 10.0,
           PreferenceKeys.isEditMode: false,
           PreferenceKeys.statusBarPolicy: StatusBarPolicy.fullExpand.rawValue,
        ])
    }
    
    static var globalKey: GlobalKeybindPreferences? {
        get {
            guard let data = UserDefaults.standard.value(forKey: PreferenceKeys.globalKey) as? Data else { return nil }
            return try? JSONDecoder().decode(GlobalKeybindPreferences.self, from: data)
        }
        
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: PreferenceKeys.globalKey)
            
            NotificationCenter.default.post(Notification(name: NotificationNames.prefsChanged, object: Preferences.globalKey))
        }
    }
    
    static var isAutoStart: Bool {
        get {
            return LaunchAtLogin.isEnabled
        }
        
        set {
            LaunchAtLogin.isEnabled = newValue
            NotificationCenter.default.post(Notification(name: NotificationNames.prefsChanged, object: Preferences.isAutoStart))
        }
    }
    
    /*
    static var isAutoStart: Bool {
        get {
            return UserDefaults.standard.bool(forKey: PreferenceKeys.isAutoStart)
        }
        
        set {
            UserDefaults.standard.set(newValue, forKey: PreferenceKeys.isAutoStart)
            
            NotificationCenter.default.post(Notification(name: NotificationNames.prefsChanged, object: Preferences.isAutoStart))
        }
    }
    */
    
    static var numberOfSecondForAutoHide: Double {
        get {
            UserDefaults.standard.double(forKey: PreferenceKeys.numberOfSecondForAutoHide)
        }
        
        set {
            UserDefaults.standard.set(newValue, forKey: PreferenceKeys.numberOfSecondForAutoHide)
            
            NotificationCenter.default.post(Notification(name: NotificationNames.prefsChanged, object: Preferences.numberOfSecondForAutoHide))
        }
    }
    
    static var isAutoHide: Bool {
        get {
            UserDefaults.standard.bool(forKey: PreferenceKeys.isAutoHide)
        }
        
        set {
            UserDefaults.standard.set(newValue, forKey: PreferenceKeys.isAutoHide)
            
            NotificationCenter.default.post(Notification(name: NotificationNames.prefsChanged, object: Preferences.isAutoHide))
        }
    }
    
    static var isShowPreference: Bool {
        get {
            UserDefaults.standard.bool(forKey: PreferenceKeys.isShowPreference)
        }
        
        set {
            UserDefaults.standard.set(newValue, forKey: PreferenceKeys.isShowPreference)
            
            NotificationCenter.default.post(Notification(name: NotificationNames.prefsChanged, object: Preferences.isShowPreference))
        }
    }
    
    static var statusBarPolicy: StatusBarPolicy {
        get {
            let value = UserDefaults.standard.integer(forKey: PreferenceKeys.statusBarPolicy)
            switch (value) {
            case 1:
                return .fullExpand
            case 2:
                return .partialExpand
            case 0:
                return .collapsed
            default:
                NSLog("Warning: Preference \"statusBarPolicy\" value undefined, default to 0")
                return .collapsed
            }
            
        }
        
        set {
            var num = -1;
            switch (newValue) {
            case .fullExpand:
                num = 1
            case .partialExpand:
                num = 2
            case .collapsed:
                num = 0
            }
            UserDefaults.standard.set(num, forKey: PreferenceKeys.statusBarPolicy)
            
            NotificationCenter.default.post(Notification(name: NotificationNames.prefsChanged, object: Preferences.statusBarPolicy))
        }
    }
    
    static var isUsingFullStatusBar: Bool {
        get {
            UserDefaults.standard.bool(forKey: PreferenceKeys.isUsingFullStatusBar)
        }
        
        set {
            UserDefaults.standard.set(newValue, forKey: PreferenceKeys.isUsingFullStatusBar)
            
            NotificationCenter.default.post(Notification(name: NotificationNames.prefsChanged, object: Preferences.isUsingFullStatusBar))
        }
    }
    
    static var isEditMode: Bool {
        get {
            UserDefaults.standard.bool(forKey: PreferenceKeys.isEditMode)
        }
        
        set {
            UserDefaults.standard.set(newValue, forKey: PreferenceKeys.isEditMode)
            
            NotificationCenter.default.post(Notification(name: NotificationNames.prefsChanged, object: Preferences.isEditMode))
        }
    }
    
}
