//
//  NSView+Extension.swift
//  vanillaClone
//
//  Created by Thanh Nguyen on 1/29/19.
//  Copyright © 2019 Console Labs. All rights reserved.
//

import Foundation
import AppKit
extension NSView {
    var getOrigin:CGPoint? {
        return self.window?.frame.origin
    }
}
