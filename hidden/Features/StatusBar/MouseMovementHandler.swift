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
            interactedWithMenuBar = false
            if mouseIsOnMenuBar {
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
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
        let windowsListInfo = CGWindowListCopyWindowInfo(options, CGWindowID(0))
        let infoList = windowsListInfo as! [[String:Any]]
        var menubarMinY: CGFloat = .nan
        for info in infoList {
            if (info["kCGWindowName"] as? String) ?? "" == "Menubar" {
                guard let bounds = info["kCGWindowBounds"],
                      let height = CGRect(dictionaryRepresentation: bounds as! CFDictionary)?.height,
                      let screenHeight = NSScreen.main?.frame.height
                else { return }
                menubarMinY = screenHeight - height
            }
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
