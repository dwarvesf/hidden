//
//  PalettePlacement.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import CoreGraphics

/// One display, as the placement sees it: AppKit coordinates (origin bottom
/// left), `visibleFrame` being the part below the menu bar.
struct PaletteScreen: Equatable {
    var frame: CGRect
    var visibleFrame: CGRect
}

/// Where the palette opens: under the arrow when the arrow is on the display
/// with the pointer, else at the right end of that display's menu bar.
enum PalettePlacement {
    static let edgeMargin: CGFloat = 8
    static let gapBelowMenuBar: CGFloat = 6

    /// The screen holding `pointer`, else the first one.
    static func screen(for pointer: CGPoint, in screens: [PaletteScreen]) -> PaletteScreen? {
        return screens.first { $0.frame.contains(pointer) } ?? screens.first
    }

    /// The panel's frame. `arrow` is the arrow's window frame in AppKit coordinates.
    static func frame(size: CGSize, arrow: CGRect?, pointer: CGPoint, screens: [PaletteScreen]) -> CGRect? {
        guard let screen = screen(for: pointer, in: screens) else { return nil }
        let area = screen.visibleFrame
        let minX = area.minX + edgeMargin
        let maxX = max(area.maxX - edgeMargin - size.width, minX)
        var x = maxX
        if let arrow, screen.frame.intersects(arrow) {
            x = min(max(arrow.midX - size.width / 2, minX), maxX)
        }
        let y = area.maxY - gapBelowMenuBar - size.height
        return CGRect(x: x, y: max(y, area.minY + edgeMargin), width: size.width, height: size.height)
    }
}
