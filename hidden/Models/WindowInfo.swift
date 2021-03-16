//
//  WindowInfo.swift
//  Hidden Bar
//
//  Created by Peter Luo on 2021/3/9.
//  Copyright © 2021 Dwarves Foundation. All rights reserved.
//

import AppKit

struct WindowInfo: Decodable {
    
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
    
    static func windowInfo(named windowName: String, type infoType: WindowInfo.InfoType) -> Any? {
        guard let windowInfos = infoList else { return nil }
        for info in windowInfos {
            if let name = info["kCGWindowName"] as? String, name == windowName {
                return info[infoType.rawValue]
            }
        }
        return nil
    }
    
    static func cgRectOfWindow(named windowName: String) -> CGRect? {
        guard let bounds = windowInfo(named: windowName, type: .bounds),
              let cgRect = CGRect(dictionaryRepresentation: bounds as! CFDictionary)
        else { return nil }
        
        return cgRect
    }
    
}
