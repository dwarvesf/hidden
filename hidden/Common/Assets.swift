//
//  Assets.swift
//  Hidden Bar
//
//  Created by Peter Luo on 2021/5/28.
//  Copyright © 2021 Dwarves Foundation. All rights reserved.
//

import AppKit

struct Assets {
    private static var expandIcon: String { Preferences.useTransparentExpandIconEnabled ? "ic_expand_hidden" : "ic_expand" }
    private static var collapseIcon: String { "ic_collapse" }
    
    static var expandImage: NSImage? {
        if (Constant.isUsingLTRLanguage) {
            return NSImage(named: NSImage.Name(expandIcon))
        } else {
            return NSImage(named: NSImage.Name(collapseIcon))
        }
    }
    static var collapseImage: NSImage? {
        if (Constant.isUsingLTRLanguage) {
            return NSImage(named: NSImage.Name(collapseIcon))
        } else {
            return NSImage(named: NSImage.Name(expandIcon))
        }
    }
}
