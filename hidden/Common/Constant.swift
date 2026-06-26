//
//  Constant.swift
//  vanillaClone
//
//  Created by Thanh Nguyen on 1/30/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import Foundation

enum Constant {
    static let appName = "Hidden Bar"

    static var isUsingLTRLanguage = false
}

extension ProcessInfo {
    // True on macOS 27 ("Golden Gate") and later, where inflating an NSStatusItem's
    // length no longer pushes neighboring menu-bar icons off-screen — the separator's
    // own backing window just grows wider than the screen instead (#360). Used to
    // gate the detect-and-degrade path so macOS <= 26 stays byte-identical. A runtime
    // check (not `#available`) so it compiles against pre-27 SDKs.
    var isMacOS27OrLater: Bool {
        isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0))
    }
}
