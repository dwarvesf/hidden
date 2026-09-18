//
//  GlobalKeybindingPreferences.swift
//  Hidden Bar
//
//  Created by phucld on 12/18/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import Foundation

struct GlobalKeybindPreferences: Codable, CustomStringConvertible {
    let function : Bool
    let control : Bool
    let command : Bool
    let shift : Bool
    let option : Bool
    let capsLock : Bool
    let carbonFlags : UInt32
    let characters : String?
    let keyCode : UInt32

    // F-keys arrive with the .function modifier flag set; rendering them as
    // "Fn18" is wrong (#191). Map the keyCode to its proper name instead.
    private var functionKeyName: String? {
        switch keyCode {
        case 122: return "F1"
        case 120: return "F2"
        case 99:  return "F3"
        case 118: return "F4"
        case 96:  return "F5"
        case 97:  return "F6"
        case 98:  return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        case 105: return "F13"
        case 107: return "F14"
        case 113: return "F15"
        case 106: return "F16"
        case 64:  return "F17"
        case 79:  return "F18"
        case 80:  return "F19"
        case 90:  return "F20"
        default:  return nil
        }
    }

    var description: String {
        var stringBuilder = ""
        if self.function && functionKeyName == nil {
            stringBuilder += "Fn"
        }
        if self.control {
            stringBuilder += "⌃"
        }
        if self.option {
            stringBuilder += "⌥"
        }
        if self.command {
            stringBuilder += "⌘"
        }
        if self.shift {
            stringBuilder += "⇧"
        }
        if self.capsLock {
            stringBuilder += "⇪"
        }
        if keyCode == 36 { // return
            stringBuilder += "⏎"
            return stringBuilder
        }
        
        if keyCode == 51 { // delete
            stringBuilder += "⌫"
            return stringBuilder
        }
        
        if keyCode == 49 { // spacer
            stringBuilder += "⎵"
            return stringBuilder
        }

        if let fKey = functionKeyName {
            stringBuilder += fKey
            return stringBuilder
        }

        if let characters = self.characters {
            stringBuilder += characters.uppercased()
        }
        
        return "\(stringBuilder)"
    }
}

extension GlobalKeybindPreferences {
    func save() {
        
    }
}
