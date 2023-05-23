//
//  NSBarButtonItem+Extension.swift
//  vanillaClone
//
//  Created by Thanh Nguyen on 1/29/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import Foundation
import AppKit

extension NSStatusBarButton {
    class func collapseBarButtonItem() -> NSStatusBarButton {
        let btnDot = NSStatusBarButton()
        btnDot.title = ""
        btnDot.sendAction(on: [.leftMouseUp, .rightMouseUp])
        btnDot.frame = NSRect(x: 0, y: 0, width: 24, height: 24)
        return btnDot
    }
}
