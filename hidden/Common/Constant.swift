//
//  Constant.swift
//  vanillaClone
//
//  Created by Thanh Nguyen on 1/30/19.
//  Copyright © 2019 Thanh Nguyen. All rights reserved.
//

import Foundation

let IS_AUTO_START = "isAutoStart"
let IS_AUTO_HIDE = "isAutoHide"
let IS_KEEP_IN_DOCK = "isKeepInDock"
let App_Name = Util.getAppName()

extension Notification.Name {
    static let killLauncher = Notification.Name("killLauncher")
}
