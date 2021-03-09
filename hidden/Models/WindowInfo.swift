//
//  WindowInfo.swift
//  Hidden Bar
//
//  Created by Peter Luo on 2021/3/9.
//  Copyright © 2021 Dwarves Foundation. All rights reserved.
//

import AppKit

struct WindowInfo: Decodable {
    
    struct Bound: Decodable {
        let Height: Int
        let Width: Int
        let X:Int
        let Y: Int
        
        var cgRect : CGRect {
            CGRect(x: X, y: Y, width: Width, height: Height)
        }
    }
    
    static var openedWindows : [WindowInfo] {
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
        let infoList = CGWindowListCopyWindowInfo(options, CGWindowID(0))
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: infoList as Any, options: .prettyPrinted)
            let windowInfos = try JSONDecoder().decode([WindowInfo].self, from: jsonData)
            let filteredWindowInfos = windowInfos
                .filter { $0.alpha == 1 }
            return filteredWindowInfos
        } catch {
            print("WindowInfo.openedWindowInfos: \(error.localizedDescription)")
        }
        
        return []
    }
    
    private enum CodingKeys : String, CodingKey {
        case alpha = "kCGWindowAlpha"
        case bounds = "kCGWindowBounds"
        case ownerName = "kCGWindowOwnerName"
        case ownerPID = "kCGWindowOwnerPID"
        case number = "kCGWindowNumber"
        case name = "kCGWindowName"
        case layer = "kCGWindowLayer"
    }
    
    init(from decoder: Decoder) throws {
        let container = try! decoder.container(keyedBy: CodingKeys.self)
        alpha = try container.decode(Int.self, forKey: CodingKeys.alpha)
        bounds = try container.decode(Bound.self, forKey: CodingKeys.bounds)
        ownerName = try container.decode(String.self, forKey: CodingKeys.ownerName)
        ownerPID = try container.decode(Int.self, forKey: CodingKeys.ownerPID)
        number = try container.decode(Int.self, forKey: CodingKeys.number)
        layer = try container.decode(Int.self, forKey: CodingKeys.layer)
        name = try? container.decode(String?.self, forKey: CodingKeys.name)
    }
    
    private let bounds: Bound
    let alpha     : Int?
    let ownerName : String
    let ownerPID  : Int
    let name      : String?
    let number    : Int
    let layer     : Int
    
    var frame: CGRect {
        bounds.cgRect
    }
    
}
