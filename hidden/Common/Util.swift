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
    
    static func setUpAutoStart(isAutoStart: Bool) {
        // SMAppService (macOS 13+) registers the main app itself as a login item;
        // no helper app, no distributed-notification kill dance.
        do {
            if isAutoStart {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status != .notRegistered {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            NSLog("AutoStart: \(isAutoStart ? "register" : "unregister") failed: \(error.localizedDescription)")
        }
        NSLog("AutoStart: SMAppService.mainApp.status = \(SMAppService.mainApp.status.rawValue)")
    }
    
    static func showPrefWindow() {
        let prefWindow = PreferencesWindowController.shared.window
        prefWindow?.bringToFront()
    }
   
}
