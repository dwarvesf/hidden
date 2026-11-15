//
//  Assets.swift
//  Hidden Bar
//
//  Created by Peter Luo on 2021/5/28.
//  Copyright © 2021 Dwarves Foundation. All rights reserved.
//

import AppKit

struct Assets {
    /// Opacity of the arrow while the bar is collapsed and stealth mode is on:
    /// nearly invisible, but still there to find and click.
    static let stealthExpandIconAlpha: CGFloat = 0.05

    /// Opacity the arrow should have. Stealth only fades the collapsed arrow;
    /// the expanded one stays fully visible.
    static func expandIconAlpha(stealthEnabled: Bool, isCollapsed: Bool) -> CGFloat {
        stealthEnabled && isCollapsed ? stealthExpandIconAlpha : 1
    }

    /// `image` drawn at `alpha`. A template image stays a template, so the menu bar
    /// still tints it for light and dark mode.
    static func image(_ image: NSImage?, alpha: CGFloat) -> NSImage? {
        guard let image, alpha < 1 else { return image }
        let faded = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: alpha)
            return true
        }
        faded.isTemplate = image.isTemplate
        return faded
    }

    static var expandImage: NSImage? {
        if (Constant.isUsingLTRLanguage) {
            return NSImage(named: NSImage.Name("ic_expand"))
        } else {
            return NSImage(named: NSImage.Name("ic_collapse"))
        }
    }
    static var collapseImage: NSImage? {
        if (Constant.isUsingLTRLanguage) {
            return NSImage(named: NSImage.Name("ic_collapse"))
        } else {
            return NSImage(named: NSImage.Name("ic_expand"))
        }
    }
}
