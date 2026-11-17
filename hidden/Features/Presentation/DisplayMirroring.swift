//
//  DisplayMirroring.swift
//  Hidden Bar
//
//  Copyright © 2026 Console Labs. All rights reserved.
//

import AppKit
import CoreGraphics

// Whether a display is mirrored, from the public CoreGraphics calls: they read
// the display configuration, so they need no Screen Recording and no other
// permission. A new or AirPlay display on its own is not a signal (an extended
// desk monitor looks the same); only mirroring means the room sees the screen.
struct DisplayMirrorReader {
    var onlineDisplays: () -> [CGDirectDisplayID]
    var isInMirrorSet: (CGDirectDisplayID) -> Bool
    // True for the display that shows another display's picture (the TV, not the
    // Mac's own screen).
    var mirrorsAnother: (CGDirectDisplayID) -> Bool
    // The display's name as macOS gives it, when it has one.
    var name: (CGDirectDisplayID) -> String?

    // The mirror now in effect, nil when no display is mirrored.
    func current() -> PresentationMirror? {
        let mirrored = onlineDisplays().filter(isInMirrorSet)
        guard !mirrored.isEmpty else { return nil }
        // Name only a display that shows another's picture: naming the Mac's own
        // screen would say it is the one mirrored.
        let shown = mirrored.filter(mirrorsAnother).compactMap(name).first
        return PresentationMirror(displayName: shown)
    }

    static let live = DisplayMirrorReader(
        onlineDisplays: {
            var ids = [CGDirectDisplayID](repeating: 0, count: 16)
            var count: UInt32 = 0
            guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success else { return [] }
            return Array(ids.prefix(Int(count)))
        },
        isInMirrorSet: { CGDisplayIsInMirrorSet($0) != 0 },
        mirrorsAnother: { CGDisplayMirrorsDisplay($0) != kCGNullDirectDisplay },
        // A display that mirrors another is often not in NSScreen.screens, so this
        // is nil for it and the copy then says "a display".
        name: { id in
            NSScreen.screens.first {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
            }?.localizedName
        })
}
