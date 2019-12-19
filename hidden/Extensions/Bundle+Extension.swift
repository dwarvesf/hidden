//
//  Bundle+Extension.swift
//  Hidden Bar
//
//  Created by phucld on 12/19/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import Foundation

extension Bundle {
    var releaseVersionNumber: String? {
        return infoDictionary?["CFBundleShortVersionString"] as? String
    }
    var buildVersionNumber: String? {
        return infoDictionary?["CFBundleVersion"] as? String
    }
}
