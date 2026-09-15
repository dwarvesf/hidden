//
//  NSView+Extension.swift
//  vanillaClone
//
//  Created by Thanh Nguyen on 1/29/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import Foundation
import AppKit
extension NSView {
    // Convert the view's own frame to screen space. On macOS <= 26 each status
    // item is its own window, so this matches window.origin; on macOS 27 the
    // whole menu bar is one window, so window.origin is shared and only the
    // view's frame distinguishes one item from another.
    var getOrigin: CGPoint? {
        guard let window = self.window else { return nil }
        return window.convertToScreen(convert(bounds, to: nil)).origin
    }
}
