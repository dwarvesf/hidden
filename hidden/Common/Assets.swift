//
//  Assets.swift
//  Hidden Bar
//
//  Created by Peter Luo on 2021/5/28.
//  Copyright © 2021 Dwarves Foundation. All rights reserved.
//

import AppKit

struct Assets {
    static var expandImage: NSImage? {
        if (Util.SharedValues.isUsingLTRLanguage) {
            return NSImage(named: NSImage.Name("ic_expand"))
        } else {
            return NSImage(named: NSImage.Name("ic_collapse"))
        }
    }
    static var collapseImage: NSImage? {
        if (Util.SharedValues.isUsingLTRLanguage) {
            return NSImage(named: NSImage.Name("ic_collapse"))
        } else {
            return NSImage(named: NSImage.Name("ic_expand"))
        }
    }
}
