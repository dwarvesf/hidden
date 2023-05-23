//
//  ContextMenuController.swift
//  Hidden Bar
//
//  Created by 上原葉 on 5/21/23.
//  Copyright © 2023 Dwarves Foundation. All rights reserved.
//

import AppKit

class ContextMenuController {
    class ContextMenuDelegate:NSObject, NSMenuDelegate {
        func confinementRect(for menu: NSMenu, on screen: NSScreen?) -> NSRect {
            guard let lscreen = screen else { return NSZeroRect }
            return lscreen.visibleFrame
        }
    }
    private static let delegate = ContextMenuDelegate()
    private static let instance = ContextMenuController()
    private let contextMenu: NSMenu
    private let prefButton: NSMenuItem
    private let editToggle: NSMenuItem
    private let quitButton: NSMenuItem
    private let seperator1 = NSMenuItem.separator()
    private let seperator2 = NSMenuItem.separator()
    private init() {
        let menu = NSMenu()
        
        let nPrefButton = NSMenuItem(title: "Preferences...".localized, action: #selector(showPreference), keyEquivalent: ",")
        nPrefButton.tag = 0
        
        
        let nEditToggle = NSMenuItem(title: "Edit Mode".localized, action: #selector(toggleEdit), keyEquivalent: "e")
        nEditToggle.tag = 1
        
        let nQuitButton = NSMenuItem(title: "Quit".localized, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        nQuitButton.tag = 2
        
        contextMenu = menu
        prefButton = nPrefButton
        editToggle = nEditToggle
        quitButton = nQuitButton
    }
    
    private func updateMenu() {
        editToggle.state = (Preferences.isEditMode) ? .on : .off
    }
    
    public static func setup() {
        instance.prefButton.target = instance
        instance.editToggle.target = instance
        instance.contextMenu.addItem(instance.prefButton)
        instance.contextMenu.addItem(instance.seperator1)
        instance.contextMenu.addItem(instance.editToggle)
        instance.contextMenu.addItem(instance.seperator2)
        instance.contextMenu.addItem(instance.quitButton)
        
        instance.contextMenu.delegate = delegate
        
        NotificationCenter.default.addObserver(forName: NotificationNames.prefsChanged, object: nil, queue: nil) {[] _ in
            instance.updateMenu()
        }
        instance.updateMenu()
    }
    
    public static func showContextMenu(_ sender: NSStatusBarButton) {
        instance.contextMenu.popUp(positioning: nil, at: .init(x: sender.bounds.minX, y: sender.bounds.minY), in: sender)
    }
    
    @objc func showPreference() {
        Util.showPrefWindow()
    }
    @objc func toggleEdit() {
        Preferences.isEditMode = !Preferences.isEditMode
    }

    
}

/*

class LegacyContextMenuController:NSViewController {
    @IBOutlet var contextMenu: NSMenu!
    @IBOutlet weak var prefButton: NSMenuItem!
    @IBOutlet weak var editToggle: NSMenuItem!
    
    static func initWithStoryboard() -> LegacyContextMenuController {
        let vc = NSStoryboard(name:"Main", bundle: nil).instantiateController(withIdentifier: "prefVC") as! LegacyContextMenuController
        return vc
    }
    
    @IBAction func openSettings(_ sender: Any) {
        Util.showPrefWindow()
    }
    
    @IBAction func toggleEdit(_ sender: Any) {
        Preferences.isEditMode = !Preferences.isEditMode
    }
    
    @IBAction func exit(_ sender: NSMenuItem) {
        NSApplication.shared.terminate(sender)
    }
    
    private func updateMenu() {
        editToggle.state = (Preferences.isEditMode) ? .on : .off
    }
    
    public func setup() {
        NotificationCenter.default.addObserver(forName: NotificationNames.prefsChanged, object: nil, queue: nil) {[weak self] notification in
            guard let target = self else {return}
            target.updateMenu()
        }
    }
    
    public func showContextMenu(_ sender: NSView) {
        instance.contextMenu!.popUp(positioning: nil, at: .init(x: sender.bounds.minX - 7, y: sender.bounds.maxY + 8), in: sender)
    }

}
 
 func locate() {
 let appleMenuBarHeight = NSScreen.main!.frame.height - NSScreen.main!.visibleFrame.height - (NSScreen.main!.visibleFrame.origin.y - NSScreen.main!.frame.origin.y) - 1
 //let mainMenuBarHeight = NSApplication.shared.mainMenu!.menuBarHeight
 let origionalPoint = sender.window!.convertPoint(toScreen: .init(x: sender.frame.minX, y: sender.frame.minY)) // left-down corner
 let point = CGPoint(x: sender.frame.minX, y: NSScreen.main!.visibleFrame.height - NSScreen.main!.frame.origin.y)
 let point2 = sender.window!.convertPoint(toScreen: .init(x: sender.frame.minX, y: sender.frame.maxY - appleMenuBarHeight))
 let point3 = NSEvent.mouseLocation
 let frame = sender.window!.convertToScreen(sender.bounds.offsetBy(dx: 0, dy: 0))
 NSLog("\(frame),\(NSScreen.main!.frame.height), \(point), \(point2)")
 let window = NSWindow.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
 window.backgroundColor = .green
 window.makeKeyAndOrderFront(NSApp)
 //CGDisplayMoveCursorToPoint(CGMainDisplayID(), .init(x: window.frame.minX, y: NSScreen.main!.frame.height - window.frame.maxY + 1));
 NSLog("\(window.frame.minX), \(window.frame.maxY)")
 
 instance.contextMenu.popUp(positioning: instance.prefButton, at: point2, in: nil)
 NSLog("CONFINE: \(instance.contextMenu.delegate?.confinementRect?(for: instance.contextMenu, on: NSScreen.main))")
 //instance.contextMenu.popUp(positioning: nil, at: .init(x: sender.bounds.minX, y: sender.bounds.minY), in: sender)
 }

*/

