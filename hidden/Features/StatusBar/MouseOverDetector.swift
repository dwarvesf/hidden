//
//  MouseOverDetector.swift
//  Hidden Bar
//
//  Created by Peter Luo on 2021/5/31.
//  Copyright © 2021 Dwarves Foundation. All rights reserved.
//

import AppKit
import os // for os_log

class MouseOverDetector {
    
    // flags
    var mouseIsInArea = false
    var mouseClickedInsideArea = false
    
    var entersAreaHandler : ()->Void
    var leavesAreaHandler : (Bool)->Void // $0: whether or not the mouse has clicked inside the area before leaving
    
    private var statusBarY  : CGFloat = .nan
    private var mouseMoveMoniter : EventMoniter?
    private var mouseClickMoniters  = [EventMoniter]()
    
    private var previousMouseLocation: CGPoint = .zero
    
    init(entersArea entersAreaHandler: @escaping ()->Void, leavesArea leavesAreaHandler: @escaping (Bool)->Void) {
        self.entersAreaHandler = entersAreaHandler
        self.leavesAreaHandler = leavesAreaHandler
        
        updateMenubarMinY()
        mouseMoveMoniter = EventMoniter(eventType: .mouseMoved, handler: mouseMoved)
        mouseClickMoniters = [
            EventMoniter(eventType: .leftMouseUp , handler: mouseClicked),
            EventMoniter(eventType: .rightMouseUp, handler: mouseClicked),
            EventMoniter(eventType: .otherMouseUp, handler: mouseClicked),
        ]
    }
    
    func start() {
        mouseMoveMoniter?.start()
        mouseClickMoniters.forEach { $0.start() }
    }
    
    func stop() {
        mouseMoveMoniter?.stop()
        mouseClickMoniters.forEach { $0.stop() }
    }
    
    private func mouseClicked(_ event: NSEvent) {
        if NSEvent.mouseLocation.y >= statusBarY { // clicks inside the status bar
            mouseClickedInsideArea = true
        }
    }
    
    private func updateMenubarMinY() {
        if let statusbarRect = WindowInfo.cgRectOfWindow(named: "Menubar"),
           let currentScreen = Util.screenWithMouse {
            // Cocoa uses top to down y coords but CoreGraphics uses down to top coords
            // To avoid convertion everytime, statusBarY is inverted on initialize
            statusBarY = currentScreen.frame.height - statusbarRect.height
        } else {
            os_log("unable to get menu bar height")
        }
    }
    
    private func mouseMoved(_ event: NSEvent) {
        // must have at least 1 pixel of difference before proceeding
        guard !(NSEvent.mouseLocation ~= previousMouseLocation) else { return }
        if NSScreen.screens.count > 1 {
            updateMenubarMinY()
        }
        
        if mouseIsInArea {
            if NSEvent.mouseLocation.y < statusBarY { // leaves area
                leavesAreaHandler(mouseClickedInsideArea)
                mouseIsInArea = false
            }
        } else {
            if NSEvent.mouseLocation.y >= statusBarY { // enters area
                mouseClickedInsideArea = false
                entersAreaHandler()
                mouseIsInArea = true
            }
        }
    }
    
}
