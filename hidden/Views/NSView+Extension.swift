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
    var position:CGPoint? {
        return self.window?.frame.origin
    }
}
