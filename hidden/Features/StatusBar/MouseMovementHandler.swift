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
    var isCollapsed     : () -> Bool
    
    var leftClickMoniter  : EventMoniter?
    var rightClickMoniter : EventMoniter?
    var mouseMoveMoniter  : EventMoniter?
    
    private var menubarMinY: CGFloat = .nan
    
    private var previousMouseLocation = NSEvent.mouseLocation
    
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
    
    init(expandHandler: @escaping ()->Void, collapseHandler: @escaping ()->Void, isCollapsed: @escaping ()->Bool) {
        self.expandHandler = expandHandler
        self.collapseHandler = collapseHandler
        self.isCollapsed = isCollapsed
        
        setupEventMoniter()
        updateAutoExpandPreferences()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateAutoExpandPreferences),
            name: .prefsChanged,
            object: nil)
    }
    
    private func setupEventMoniter() {
        leftClickMoniter  = EventMoniter(mask: .leftMouseDown, handler: mouseClicked)
        rightClickMoniter = EventMoniter(mask: .rightMouseDown, handler: mouseClicked)
        mouseMoveMoniter  = EventMoniter(mask: .mouseMoved, handler: mouseMoved)
    }
    
    @objc private func updateAutoExpandPreferences() {
        if Preferences.autoExpand {
            leftClickMoniter?.start()
            rightClickMoniter?.start()
            mouseMoveMoniter?.start()
        } else {
            leftClickMoniter?.stop()
            rightClickMoniter?.stop()
            mouseMoveMoniter?.stop()
        }
    }
    
    private func updateMenubarMinY() {
        // Cocoa uses top left coords, but CG uses bottom left coords
        // To avoid convertion everytime, menubarMinY is inverted on initialize
        guard let screenHeight = Util.screenWithMouse?.frame.height,
              let menubarFrame = WindowInfo.cgRectOfWindow(named: "Menubar")
        else {
            return
        }
        
        menubarMinY = screenHeight - menubarFrame.height
    }
    
    private func mouseMoved(_ event: NSEvent) {
        
        if !isCollapsed() && !(NSEvent.mouseLocation ~= previousMouseLocation) {
            updateMenubarMinY()
            previousMouseLocation = NSEvent.mouseLocation
        }
        
        if NSEvent.mouseLocation.y >= menubarMinY {
            self.mouseIsOnMenuBar = true
        } else {
            self.mouseIsOnMenuBar = false
        }
        
    }
    
    private func mouseClicked(_ event: NSEvent) {
        if NSEvent.mouseLocation.y >= self.menubarMinY {
            self.interactedWithMenuBar = true
        } else {
            self.interactedWithMenuBar = false
        }
    }
    
}
