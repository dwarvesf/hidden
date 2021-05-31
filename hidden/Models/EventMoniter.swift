//
//  EventMoniter.swift
//  Hidden Bar
//
//  Created by Peter Luo on 2021/5/31.
//  Copyright © 2021 Dwarves Foundation. All rights reserved.
//

import AppKit

class EventMoniter {
    
    var globalMoniter : Any?
    var localMoniter  : Any?
    var handler       : (NSEvent)->Void
    var eventType     : NSEvent.EventTypeMask
    
    init(eventType: NSEvent.EventTypeMask, handler: @escaping (NSEvent)->Void) {
        self.handler = handler
        self.eventType = eventType
    }
    
    func start() {
        globalMoniter = NSEvent.addGlobalMonitorForEvents(matching: eventType, handler: handler)
        localMoniter  = NSEvent.addLocalMonitorForEvents(matching: eventType) { event in
            self.handler(event)
            return event
        }
    }
    
    func stop() {
        globalMoniter = nil
        localMoniter  = nil
    }
    
    deinit {
        stop()
    }
    
}
