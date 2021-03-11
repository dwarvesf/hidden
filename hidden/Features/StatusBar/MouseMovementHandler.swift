//
//  MouseMovementHandler.swift
//  Hidden Bar
//
//  Created by Peter Luo on 2021/3/4.
//  Copyright © 2021 Dwarves Foundation. All rights reserved.
//

import AppKit

class MouseMovementHandler {
    
    var expandHandler   : () -> Void
    var collapseHandler : () -> Void
    
    private var mouseMoveMoniter : GlobalEventMoniter?
    private var mouseClickMoniter : GlobalEventMoniter?
    
    private var interactedWithMenuBar = false
    private var mouseIsOnMenuBar      = false {
        didSet {
            guard mouseIsOnMenuBar != oldValue else { return }
            if mouseIsOnMenuBar {
                interactedWithMenuBar = false
                expandHandler()
            } else if !interactedWithMenuBar {
                collapseHandler()
            }
        }
    }
    
    init(expandHandler: @escaping ()->Void, collapseHandler: @escaping ()->Void) {
        self.expandHandler = expandHandler
        self.collapseHandler = collapseHandler
        
        setupEventMoniter()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateAutoExpandPreferences),
            name: .prefsChanged,
            object: nil)
        
        updateAutoExpandPreferences()
    }
    
    private func setupEventMoniter() {
        // get menu bar height
        guard let screenHeight = NSScreen.main?.frame.height else {
            print("Failed to setup MouseMovementEventMonitor: Unable to get screen height")
            return  
        }
        var menubarMinY: CGFloat = .nan
        
        if let menubarWindow = WindowInfo.windowNamed("Menubar") {
            menubarMinY = screenHeight - menubarWindow.frame.height
        }
        
        if menubarMinY == .nan {
            print("Unable to get Menubar window height")
            return
        }
        
        // setup mouse move event moniter
        mouseMoveMoniter = GlobalEventMoniter(mask: .mouseMoved) { event in
            if NSEvent.mouseLocation.y >= menubarMinY {
                // for some reason, NSEvent.mouseLocation gives out inverted y coords
                self.mouseIsOnMenuBar = true
            } else {
                self.mouseIsOnMenuBar = false
            }
        }
        
        // setup mouse click event moniter
        mouseClickMoniter = GlobalEventMoniter(mask: .leftMouseDown, handler: { event in
            if NSEvent.mouseLocation.y >= menubarMinY {
                self.interactedWithMenuBar = true
            } else {
                self.interactedWithMenuBar = false
            }
        })
    }
    
    @objc private func updateAutoExpandPreferences() {
        if Preferences.autoExpand {
            mouseMoveMoniter?.start()
            mouseClickMoniter?.start()
        } else {
            mouseMoveMoniter?.stop()
            mouseClickMoniter?.stop()
        }
    }
    
}
