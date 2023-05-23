//
//  String+Extension.swift
//  Hidden Bar
//
//  Created by Licardo on 2020/3/9.
//  Copyright © 2020 Dwarves Foundation. All rights reserved.
//

import Foundation

extension String {
    
    // localize
    var localized: String {
        return NSLocalizedString(self, comment: self)
    }
}
