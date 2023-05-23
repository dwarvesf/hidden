//
//  Global.swift
//  Hidden Bar
//
//  Created by 上原葉 on 5/16/23.
//  Copyright © 2023 Dwarves Foundation. All rights reserved.
//

import AppKit

extension Global { // Global Variables for Product
    // Detects RTL type system
    public static let isUsingLTRTypeSystem = (NSApplication.shared.userInterfaceLayoutDirection == .leftToRight);
    
    // Get main operation queue
    public static let mainQueue = OperationQueue.main
    
    // Get main runloop
    public static let runLoop = RunLoop.main
}
