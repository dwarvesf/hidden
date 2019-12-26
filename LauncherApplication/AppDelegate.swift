//
//  AppDelegate.swift
//  LauncherApplication
//
//  Created by Thanh Nguyen on 1/28/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import Cocoa


@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    
    @objc func terminate() {
        NSApp.terminate(nil)
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let mainAppIdentifier = "com.dwarvesv.minimalbar"
        let runningApps = NSWorkspace.shared.runningApplications
        let isRunning = !runningApps.filter { $0.bundleIdentifier == mainAppIdentifier }.isEmpty
        
        if !isRunning {
            DistributedNotificationCenter.default().addObserver(self,
                                                                selector: #selector(self.terminate),
                                                                name: Notification.Name.killLauncher,
                                                                object: mainAppIdentifier)
            
            let path = Bundle.main.bundlePath as NSString
            var components = path.pathComponents
            components.removeLast(3)
            components.append("MacOS")
            let appName = "Hidden Bar"
            components.append(appName) //main app name
            let newPath = NSString.path(withComponents: components)
            NSWorkspace.shared.launchApplication(newPath)
        }
        else {
            self.terminate()
        }
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
    
    
}

