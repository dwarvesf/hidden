//
//  Preferences.swift
//  Hidden Bar
//
//  Created by phucld on 12/18/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import Foundation

enum Preferences {
    static var globalKey: GlobalKeybindPreferences? {
        get {
            guard let data = UserDefaults.standard.value(forKey: UserDefaults.Key.globalKey) as? Data else { return nil }
            return try? JSONDecoder().decode(GlobalKeybindPreferences.self, from: data)
        }
        
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: UserDefaults.Key.globalKey)
        }
    }
    
    static var isAutoStart: Bool {
        get {
            return UserDefaults.standard.bool(forKey: UserDefaults.Key.isAutoStart)
        }
        
        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.isAutoStart)
            
            Util.setUpAutoStart(isAutoStart: newValue)
        }
    }
    
    static var numberOfSecondForAutoHide: Double {
        get {
            UserDefaults.standard.double(forKey: UserDefaults.Key.numberOfSecondForAutoHide)
        }
        
        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.numberOfSecondForAutoHide)
        }
    }
    
    static var isAutoHide: Bool {
        get {
            UserDefaults.standard.bool(forKey: UserDefaults.Key.isAutoHide)
        }
        
        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.isAutoHide)
        }
    }
    
    static var isShowPreference: Bool {
        get {
            UserDefaults.standard.bool(forKey: UserDefaults.Key.isShowPreference)
        }
        
        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.isShowPreference)
        }
    }
    
    static var areSeparatorsHidden: Bool {
        get {
            UserDefaults.standard.bool(forKey: UserDefaults.Key.areSeparatorsHidden)
        }
        
        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.areSeparatorsHidden)
        }
    }
    
    static var alwaysHiddenModeEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: UserDefaults.Key.alwaysHiddenModeEnabled)
        }
        
        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.alwaysHiddenModeEnabled)
        }
    }
}
