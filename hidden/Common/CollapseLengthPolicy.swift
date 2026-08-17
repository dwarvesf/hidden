//
//  CollapseLengthPolicy.swift
//  Hidden Bar
//

import Foundation

enum CollapseLengthPolicy {
    private static let macOS27Margin = 64.0

    static func collapsedLength(
        screenWidths: [Double],
        macOSMajorVersion: Int,
        hideWithMixedDisplays: Bool = false
    ) -> Double {
        let widestScreenWidth = screenWidths.max() ?? 1728

        guard macOSMajorVersion >= 27 else {
            return max(500, min(widestScreenWidth * 2, 10_000))
        }

        // macOS 27 drops a status item at half the display width. Staying below
        // that limit lets the system move the displaced icons into its overflow.
        let narrowestScreenWidth = screenWidths.min() ?? widestScreenWidth
        if widestScreenWidth > narrowestScreenWidth && !hideWithMixedDisplays {
            // One NSStatusItem length is shared by all menu bars. On displays of
            // different widths no one length can clear both bars, so make macOS
            // discard it on every bar rather than visibly shifting icons on wider
            // displays. Users can opt into hiding on the narrowest display.
            return floor(widestScreenWidth / 2 + macOS27Margin)
        }
        let belowHalfWidthLimit = max(0, floor(narrowestScreenWidth / 2) - 1)
        return min(max(200, floor(narrowestScreenWidth / 2 - macOS27Margin)), belowHalfWidthLimit)
    }
}
