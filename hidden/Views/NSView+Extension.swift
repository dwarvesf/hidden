//
//  NSView+Extension.swift
//  vanillaClone
//
//  Created by Thanh Nguyen on 1/29/19.
//  Copyright © 2019 Thanh Nguyen. All rights reserved.
//

import Foundation
import AppKit
extension NSView {
    var getOrigin:CGPoint? {
        return self.window?.frame.origin
    }
}
