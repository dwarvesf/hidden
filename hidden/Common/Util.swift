//
//  Util.swift
//  vanillaClone
//
//  Created by Thanh Nguyen on 1/29/19.
//  Copyright © 2019 Console Labs. All rights reserved.
//

import AppKit
import Foundation


class Util {
    
    @discardableResult
    static func setUpAutoStart(isAutoStart: Bool, takingOver: Bool = false) -> Bool {
        // SMAppService (macOS 13+) registers the main app itself as a login item;
        // no helper app, no distributed-notification kill dance.
        return AutoStart.applyUnlessTesting(enabled: isAutoStart, takingOver: takingOver)
    }
    
    static func showPrefWindow() {
        let prefWindow = PreferencesWindowController.shared.window
        prefWindow?.bringToFront()
    }
   
}
