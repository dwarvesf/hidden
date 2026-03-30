//
//  Notification.Name+Extension.swift
//  Hidden Bar
//
//  Created by Peter Luo on 2020/6/26.
//  Copyright © 2020 Dwarves Foundation. All rights reserved.
//

import Cocoa

extension Notification.Name {
    
    static let prefsChanged = Notification.Name("prefsChanged")
    static let alwayHideToggle = Notification.Name("alwayHideToggle")
    static let notchOverflowToggle = Notification.Name("notchOverflowToggle")
}
