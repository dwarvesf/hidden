//
//  PreferencesWindowController.swift
//  Hidden Bar
//
//  Created by Phuc Le Dien on 2/22/19.
//  Copyright © 2019 Thanh Nguyen. All rights reserved.
//

import Cocoa

class PreferencesWindowController: NSWindowController {

    override func windowDidLoad() {
        super.windowDidLoad()
    
        // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
    }
    
    static let shared: PreferencesWindowController = {
        let storyboard = NSStoryboard(name:"Main", bundle: nil)
        let controller = storyboard.instantiateController(withIdentifier: "MainWindow")
        return controller as! PreferencesWindowController
    }()

}
