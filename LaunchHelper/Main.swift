//
//  main.swift
//  LaunchHelper
//
//  Created by 上原葉 on 5/22/23.
//  Copyright © 2023 Dwarves Foundation. All rights reserved.
//

import AppKit

@main struct MyApp {
    
    private static var runningApp: NSRunningApplication? = nil
    
    static func main () async -> Void {
        // Check for duplicated instances.
        let otherRunningInstances = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == Global.launcherAppId && $0 != NSRunningApplication.current
        }
        let isAppAlreadyRunning = !otherRunningInstances.isEmpty
        
        if (isAppAlreadyRunning) {
            
            NSLog("Program already running: \(otherRunningInstances.map{$0.processIdentifier}).")
            return;
        }
        
        // Wake up main Application
        var mainAppPath2 = Bundle.main.bundlePath
        let mainAppPath = "/Users/ueharayou/Applications/WireGuard.app"
        //mainAppPath.removeLast(3)
        guard FileManager.default.fileExists(atPath: mainAppPath) else {
            NSLog("Program not found: \(mainAppPath).")
            return;
        }
        guard let pathURL = URL (string: mainAppPath) else {
            NSLog("Url failed.")
            return
        }
        
        if #available(macOS 10.15, *) {
            
            do {
                try await runningApp = NSWorkspace.shared.openApplication(at: pathURL, configuration: NSWorkspace.OpenConfiguration())
            } catch {
                NSLog("Program Launch Failed: \(error).")
            }
        }
        else {
            do {
                try runningApp = NSWorkspace.shared.launchApplication(at: pathURL, configuration: [:])
            } catch {
                NSLog("Program Launch Failed: \(error).")
            }
            
            while (!runningApp!.isTerminated) {
                continue
            }
        }
        NSLog("Program Exiting.")
    }
}

/*
 if #available(macOS 10.15, *) {
     NSLog("\(Bundle.allBundles)")
     var path = Bundle.main.bundlePath as NSString
     for _ in 0...3 {
         path = path.deletingLastPathComponent as NSString
     }
     let applicationPathString = path as String
     guard let pathURL = URL (string: applicationPathString) else { return }
     NSWorkspace.shared.openApplication (at: pathURL, configuration:NSWorkspace.OpenConfiguration()) {[] (app, error) in
         if (app != nil) {
             NSLog("App Fetched: \(app!)")
         }
         else {
             NSLog("Error! \(error ?? NSError())")
             exit(-1)
         }
     }
 }
 else {
     let path = Bundle.main.bundlePath as NSString
     var components = path.pathComponents
     components.removeLast(3)
     components.append("MacOS")
     let appName = "Minimal Bar"
     components.append(appName) //main app name
     let newPath = NSString.path(withComponents: components)
     NSWorkspace.shared.launchApplication(newPath)
 }
 */
