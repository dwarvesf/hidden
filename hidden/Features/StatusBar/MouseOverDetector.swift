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
    
    private var statusBarY  : CGFloat
    private var mouseMoveMoniter : EventMoniter?
    private var mouseClickMoniters  = [EventMoniter]()
    
    init(entersArea entersAreaHandler: @escaping ()->Void, leavesArea leavesAreaHandler: @escaping (Bool)->Void) {
        self.entersAreaHandler = entersAreaHandler
        self.leavesAreaHandler = leavesAreaHandler
        
        if let statusbarRect = WindowInfo.cgRectOfWindow(named: "Menubar"),
           let currentScreen = NSScreen.main {
            // Cocoa uses top to down y coords but CoreGraphics uses down to top coords
            // To avoid convertion everytime, statusBarY is inverted on initialize
            statusBarY = currentScreen.frame.height - statusbarRect.height
            print(statusbarRect.height)
        } else {
            os_log("Unable to get status bar height")
            statusBarY = .nan
        }
        mouseMoveMoniter = EventMoniter(eventType: .mouseMoved, handler: mouseMoved)
        mouseClickMoniters = [
            EventMoniter(eventType: .leftMouseUp , handler: mouseClicked),
            EventMoniter(eventType: .rightMouseUp, handler: mouseClicked),
            EventMoniter(eventType: .otherMouseUp, handler: mouseClicked),
        ]
        
        mouseMoveMoniter?.start()
        mouseClickMoniters.forEach { $0.start() }
    }
    
    private func mouseClicked(_ event: NSEvent) {
        if NSEvent.mouseLocation.y >= statusBarY { // clicks inside the status bar
            mouseClickedInsideArea = true
        }
    }
    
    private func mouseMoved(_ event: NSEvent) {
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
