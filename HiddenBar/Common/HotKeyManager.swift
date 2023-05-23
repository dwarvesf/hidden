//
//  HotKeyManager.swift
//  Hidden Bar
//
//  Created by 上原葉 on 5/24/23.
//  Copyright © 2023 Dwarves Foundation. All rights reserved.
//

import Foundation
import HotKey

class HotKeyManager {
    static var hotKey: HotKey? {
        didSet {
            guard let hotKey = hotKey else { return }
            
            hotKey.keyDownHandler = { [] in
                switch (Preferences.statusBarPolicy) {
                case (.collapsed):
                    Preferences.statusBarPolicy = .partialExpand
                default:
                    Preferences.statusBarPolicy = .collapsed
                }
                //StatusBarController.triggerAdjustment()
            }
        }
    }
    
    
    static func setupHotKey() {
        guard let globalKey = Preferences.globalKey else {return}
        hotKey = HotKey(keyCombo: KeyCombo(carbonKeyCode: globalKey.keyCode, carbonModifiers: globalKey.carbonFlags))
    }
}
