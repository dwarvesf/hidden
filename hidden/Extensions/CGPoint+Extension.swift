//
//  CGPoint+Extension.swift
//  Hidden Bar
//
//  Created by Peter Luo on 2021/3/17.
//  Copyright © 2021 Dwarves Foundation. All rights reserved.
//

import Foundation

extension CGPoint {
    static func ~=(lhs: CGPoint, rhs: CGPoint) -> Bool {
        Int(lhs.x) == Int(rhs.x) && Int(lhs.y) == Int(rhs.y)
    }
}
