//
//  NSWindow+Extension.swift
//  Hidden Bar
//
//  Created by phucld on 3/6/20.
//  Copyright © 2020 Console Labs. All rights reserved.
//

import AppKit

extension NSWindow {
    func bringToFront() {
        self.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

