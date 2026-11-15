//
//  Assets.swift
//  Hidden Bar
//
//  Created by Peter Luo on 2021/5/28.
//  Copyright © 2021 Dwarves Foundation. All rights reserved.
//

import AppKit

/// The look of the expand/collapse arrow (issue #310). The raw value is what
/// Preferences stores, so renaming a case orphans users' saved choice.
enum ArrowStyle: String, CaseIterable {
    /// The shipped arrow artwork; also what a fresh install gets.
    case arrow
    case chevron
    case dot
    case line

    static let `default`: ArrowStyle = .arrow

    /// Anything unknown or missing reads as the default, never as "no arrow".
    init(storedValue: String?) {
        self = storedValue.flatMap(ArrowStyle.init(rawValue:)) ?? .default
    }

    /// English text, which is also the Localizable.strings key.
    var localizedNameKey: String {
        switch self {
        case .arrow: return "Arrow"
        case .chevron: return "Chevron"
        case .dot: return "Dot"
        case .line: return "Line"
        }
    }

    var localizedName: String { localizedNameKey.localized }

    /// Shown while the bar is collapsed: clicking it expands.
    func expandImage(isLTR: Bool = Constant.isUsingLTRLanguage) -> NSImage? {
        image(isCollapsed: true, isLTR: isLTR)
    }

    /// Shown while the bar is expanded: clicking it collapses.
    func collapseImage(isLTR: Bool = Constant.isUsingLTRLanguage) -> NSImage? {
        image(isCollapsed: false, isLTR: isLTR)
    }

    /// Both states side by side, for the Preferences popup. A template, so the
    /// menu tints it for its own highlight.
    func previewImage(isLTR: Bool = Constant.isUsingLTRLanguage) -> NSImage {
        let glyphs = [expandImage(isLTR: isLTR), collapseImage(isLTR: isLTR)].compactMap { $0 }
        let cell: CGFloat = 18, gap: CGFloat = 4
        let size = NSSize(width: cell * CGFloat(glyphs.count) + gap * CGFloat(max(glyphs.count - 1, 0)), height: cell)
        let preview = NSImage(size: size, flipped: false) { _ in
            for (index, glyph) in glyphs.enumerated() {
                let scale = min(cell / glyph.size.width, cell / glyph.size.height, 1)
                let drawn = NSSize(width: glyph.size.width * scale, height: glyph.size.height * scale)
                let origin = NSPoint(x: (cell + gap) * CGFloat(index) + (cell - drawn.width) / 2,
                                     y: (cell - drawn.height) / 2)
                glyph.draw(in: NSRect(origin: origin, size: drawn))
            }
            return true
        }
        preview.isTemplate = true
        return preview
    }

    // The collapsed arrow points toward the hidden icons ("<" on an LTR menu
    // bar); the expanded one points back. Right-to-left languages mirror both.
    private func image(isCollapsed: Bool, isLTR: Bool) -> NSImage? {
        let pointsLeft = isCollapsed == isLTR
        switch self {
        case .arrow:
            return NSImage(named: NSImage.Name(pointsLeft ? "ic_expand" : "ic_collapse"))
        case .chevron:
            return Self.symbol(pointsLeft ? "chevron.left" : "chevron.right", pointSize: 12, weight: .medium)
        case .dot:
            return Self.symbol(isCollapsed ? "circle.fill" : "circle", pointSize: 8, weight: .regular)
        case .line:
            return Self.lineImage(length: isCollapsed ? 7 : 14)
        }
    }

    private static func symbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
        image?.isTemplate = true
        return image
    }

    /// A thin horizontal bar drawn as a template: short while collapsed, long
    /// while expanded, so the two states still read apart.
    private static func lineImage(length: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            let bar = NSRect(x: rect.midX - length / 2, y: rect.midY - 0.75, width: length, height: 1.5)
            NSColor.black.setFill()
            NSBezierPath(roundedRect: bar, xRadius: 0.75, yRadius: 0.75).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}

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

    /// The status item's image for one state: the chosen style, faded when stealth
    /// mode is on and the bar is collapsed.
    static func toggleImage(style: ArrowStyle, isCollapsed: Bool, stealthEnabled: Bool,
                            isLTR: Bool = Constant.isUsingLTRLanguage) -> NSImage? {
        let base = isCollapsed ? style.expandImage(isLTR: isLTR) : style.collapseImage(isLTR: isLTR)
        return image(base, alpha: expandIconAlpha(stealthEnabled: stealthEnabled, isCollapsed: isCollapsed))
    }

    static var expandImage: NSImage? {
        Preferences.arrowStyle.expandImage()
    }
    static var collapseImage: NSImage? {
        Preferences.arrowStyle.collapseImage()
    }
}
