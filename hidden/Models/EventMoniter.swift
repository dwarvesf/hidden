//
//  EventMoniter.swift
//  Hidden Bar
//
//  Created by Peter Luo on 2021/3/3.
//  Copyright © 2021 Dwarves Foundation. All rights reserved.
//

import Cocoa

class EventMoniter {
    
    var globalMoniter: Any?
    var localMoniter : Any?
    
    let mask: NSEvent.EventTypeMask
    let handler: (NSEvent) -> ()
    var isStarted : Bool {
        return self.globalMoniter != nil
    }
    
    init(mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> ()) {
        self.mask = mask
        self.handler = handler
    }
    
    deinit {
        stop()
    }
    
    func start() {
        guard !isStarted else { return }
        self.globalMoniter = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler)
        self.localMoniter  = NSEvent.addLocalMonitorForEvents(matching: mask) { self.handler($0) ; return $0 }
    }
    
    func stop() {
        guard isStarted else { return }
        NSEvent.removeMonitor(self.globalMoniter!)
        NSEvent.removeMonitor(self.localMoniter!)
        globalMoniter = nil
        localMoniter  = nil
    }
    
}
