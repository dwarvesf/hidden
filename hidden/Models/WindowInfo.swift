//
//  WindowInfo.swift
//  Hidden Bar
//
//  Created by Peter Luo on 2021/5/31.
//  Copyright © 2021 Dwarves Foundation. All rights reserved.
//

import AppKit

class WindowInfo {
    
    enum InfoType : String {
         case alpha = "kCGWindowAlpha"
         case bounds = "kCGWindowBounds"
         case ownerName = "kCGWindowOwnerName"
         case ownerPID = "kCGWindowOwnerPID"
         case number = "kCGWindowNumber"
         case name = "kCGWindowName"
         case layer = "kCGWindowLayer"
    }
    
    static var infoList : [ [ String : Any ] ]? {
         let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
         guard let infoList = CGWindowListCopyWindowInfo(options, CGWindowID(0)) else { return nil }
         return (infoList as! [[String : Any]])
     }
    
    static func infoFor(windowNamed windowName: String, infoType: WindowInfo.InfoType) -> Any? {
        guard let infoList = WindowInfo.infoList else { return nil }
        for info in infoList {
            if let name = info["kCGWindowName"] as? String, name == windowName {
                return info[infoType.rawValue]
            }
        }
        return nil
    }
    
    static func cgRectOfWindow(named windowName: String) -> CGRect? {
        guard let bounds = WindowInfo.infoFor(windowNamed: windowName, infoType: .bounds),
               let cgRect = CGRect(dictionaryRepresentation: bounds as! CFDictionary)
         else { return nil }

         return cgRect
     }
    
}
