//
//  PreferencesWindow.swift
//  Hidden Bar
//
//  Created by Peter Luo on 2019/12/21.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import Cocoa

class PreferencesWindow: NSWindow {
    
    var activateHandler : ()->Void = {}
    var closeHandler : ()->Void = {}
    
    func windowClosedHandler(_ handler: @escaping ()->Void) {
        closeHandler = handler
    }
    
    override func close() {
        closeHandler()
        super.close()
    }
}
