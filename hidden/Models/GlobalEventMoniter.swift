//
//  GlobalEventMoniter.swift
//  Hidden Bar
//
//  Created by Peter Luo on 2021/3/3.
//  Copyright © 2021 Dwarves Foundation. All rights reserved.
//

import Cocoa

class GlobalEventMoniter {
    
    static func grantAccess() -> Bool {
        let accessEnabled = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        return accessEnabled
    }
    
    var monitor: Any?
    let mask: NSEvent.EventTypeMask
    let handler: (NSEvent) -> ()
    var isStarted : Bool {
        return self.monitor != nil
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
        self.monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler)
    }
    
    func stop() {
        guard isStarted else { return }
        NSEvent.removeMonitor(self.monitor!)
        self.monitor = nil
    }
    
}
