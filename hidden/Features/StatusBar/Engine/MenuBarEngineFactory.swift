//
//  MenuBarEngineFactory.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import Foundation

// The single place that picks a hiding mechanism for the running OS.
enum MenuBarEngineFactory {
    static func make(items: MenuBarItemProvider) -> MenuBarEngine {
        // macOS 27 ejects an inflated separator from the menu bar (#360). The
        // direct build hides natively there instead. The App Store build cannot:
        // the sandbox blocks the Accessibility reads that locate the sections.
        #if HIDDENBAR_NATIVE_VISIBILITY
        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 {
            return NativeVisibilityEngine(items: items)
        }
        #endif
        return LegacyLengthEngine(items: items)
    }
}
