//
//  UserDefault+Extension.swift
//  Hidden Bar
//
//  Created by phucld on 12/18/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import Foundation

extension UserDefaults {
    enum Key {
        static let globalKey = "globalKey"
        static let numberOfSecondForAutoHide = "numberOfSecondForAutoHide"
        static let isAutoStart = "isAutoStart"
        static let isAutoHide = "isAutoHide"
        static let isShowPreference = "isShowPreferences"
        static let autoExpandCollapse = "autoExpandCollapse"
        static let areSeparatorsHidden = "areSeparatorsHidden"
        static let alwaysHiddenSectionEnabled = "alwaysHiddenSectionEnabled"
        static let useFullStatusBarOnExpandEnabled = "useFullStatusBarOnExpandEnabled"
    }
    
    open override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        print("hi!")
    }
}
