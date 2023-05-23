//
//  SelectedSecond.swift
//  Hidden Bar
//
//  Created by phucld on 12/18/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import Foundation

enum SelectedSecond: Int {
       case fiveSeconds = 0
       case tenSeconds = 1
       case fifteenSeconds = 2
       case thirdtySeconds = 3
       case oneMinus = 4
       
       func toSeconds() -> Double {
           switch self {
           case .fiveSeconds:
               return 5.0
           case .tenSeconds:
               return 10.0
           case .fifteenSeconds:
               return 15.0
           case .thirdtySeconds:
               return 30.0
           case .oneMinus:
               return 60.0
           }
       }
       
       static func secondToPossition(seconds: Double) -> Int {
           switch seconds {
           case 10.0:
               return 1
           case 15.0:
               return 2
           case 30.0:
               return 3
           case 60.0:
               return 4
           default:
               return 0
           }
       }
   }
