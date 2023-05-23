//
//  StatusBarController.swift
//  vanillaClone
//
//  Created by Thanh Nguyen on 1/30/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import AppKit

enum StatusBarPolicy:Int {
    case  collapsed = 0, fullExpand = 1, partialExpand = 2
}

class StatusBarController {
    
    //MARK: - Variables
    //private let autoCollapseTimer:Timer
    
    //MARK: - BarItems
    
    private let masterToggle = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let primarySeprator = NSStatusBar.system.statusItem(withLength: 0)
    private let secondarySeprator = NSStatusBar.system.statusItem(withLength: 0)
    private let updateLock = NSLock()
    private var autoCollapseTimer: Timer? = nil
    
    private static let hiddenSepratorLength: CGFloat =  0
    private static let normalSepratorLength: CGFloat =  10
    private static let expandedSeperatorLength: CGFloat = 10000

    private var areSeperatorPositionValid: Bool {
        guard
            let toggleButtonX = masterToggle.button?.getOrigin?.x,
            let primarySepratorX = primarySeprator.button?.getOrigin?.x,
            let secondarySepratorX = secondarySeprator.button?.getOrigin?.x
            else {return false}
        
        if Global.isUsingLTRTypeSystem {
            return toggleButtonX >= primarySepratorX && primarySepratorX >= secondarySepratorX
        } else {
            return toggleButtonX <= primarySepratorX && primarySepratorX <= secondarySepratorX
        }
    }

    @objc private static func toggleButtonPressed(sender: NSStatusBarButton) {
        if let event = NSApp.currentEvent {
            
            let isOptionKeyPressed = event.modifierFlags.contains(NSEvent.ModifierFlags.option)
            let isControlKeyPressed = event.modifierFlags.contains(NSEvent.ModifierFlags.control)
            
            switch (event.type, isOptionKeyPressed, isControlKeyPressed) {
            case (NSEvent.EventType.leftMouseUp, false, false):
                if (Preferences.statusBarPolicy != .collapsed) {Preferences.statusBarPolicy  = .collapsed}
                else {Preferences.statusBarPolicy = .partialExpand}
                Preferences.isEditMode = false
            case (NSEvent.EventType.leftMouseUp, true, false):
                if (Preferences.statusBarPolicy != .collapsed) {Preferences.statusBarPolicy  = .collapsed}
                else {Preferences.statusBarPolicy = .fullExpand}
                Preferences.isEditMode = false
            case (NSEvent.EventType.rightMouseUp, _, _):
                fallthrough
            case (NSEvent.EventType.leftMouseUp, _, true):
                ContextMenuController.showContextMenu(sender)
            default:
                break
            }
        }
    }
    
    //MARK: - Methods
    private static let instance = StatusBarController()
    private init() {
        masterToggle.autosaveName = "hiddenbar_masterToggle";
        primarySeprator.autosaveName = "hiddenbar_primarySeprator";
        secondarySeprator.autosaveName = "hiddenbar_secondarySeprator";
        NSLog("Status bar controller inited.")
    }
    
    public static func setup() {
        ContextMenuController.setup()
        
        let masterToggle = instance.masterToggle,
        primarySeprator = instance.primarySeprator,
        secondarySeprator = instance.secondarySeprator
        
        if let button = masterToggle.button {
            button.image = Assets.collapseImage
            button.target = self
            button.action = #selector(toggleButtonPressed(sender:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        //let menu = StatusBarMenuManager.getContextMenu()
        //masterToggle.menu = menu
        
        if let button = primarySeprator.button {
            button.image = Assets.seperatorImage
        }
        
        if let button = secondarySeprator.button {
            button.image = Assets.seperatorImage
            button.appearsDisabled = true
        }
        
        NotificationCenter.default.addObserver(forName: NotificationNames.prefsChanged, object: nil, queue: Global.mainQueue) {[] (notification) in
            //guard let target = self else {return}
            triggerAdjustment()
        }
        
        // Manually adjusting the bar once
        triggerAdjustment()
        
    }
    
    private static func triggerAdjustment() {
        resetAutoCollapseTimer()
        adjustStatusBar()
        adjustMenuBar()
    }
    
    private static func resetAutoCollapseTimer () {
        let lock = instance.updateLock
        do {
            lock.lock(before: Date(timeIntervalSinceNow: 1))
            defer {lock.unlock()}
            //NSLog("Timer Cancelled:\(String(describing: instance.autoCollapseTimer)).")
            instance.autoCollapseTimer?.invalidate()
            switch (Preferences.isAutoHide, Preferences.isEditMode, Preferences.statusBarPolicy) {
            case (false, _, _), (_, true, _), (_, _, .collapsed):
                return
            default:
                break
            }
            let timer = Timer(timeInterval: TimeInterval(Preferences.numberOfSecondForAutoHide), repeats: false) {
                [] (timer:Timer) in
                //NSLog("Timer Triggered:\(timer).")
                Preferences.statusBarPolicy = .collapsed
                return
            }
            //NSLog("Timer Dispatched:\(timer).")
            Global.runLoop.add(timer, forMode: .common)
            instance.autoCollapseTimer = timer
        }
    }
    
    private static func adjustStatusBar () {
        let masterToggle = instance.masterToggle,
            primarySeprator = instance.primarySeprator,
            secondarySeprator = instance.secondarySeprator,
            lock = instance.updateLock
        
        lock.lock(before: Date(timeIntervalSinceNow: 1))
        if Preferences.isEditMode {
            //NSLog("EDIT")
            primarySeprator.length = StatusBarController.normalSepratorLength
            //primarySeprator.isVisible = true
            secondarySeprator.length = StatusBarController.normalSepratorLength
            //secondarySeprator.isVisible = true
            masterToggle.button?.image = Assets.expandImage
            
        }
        else {
            //NSLog("NONEDIT, \(Preferences.statusBarPolicy)")
            switch Preferences.statusBarPolicy {
            case .fullExpand:
                primarySeprator.length = StatusBarController.hiddenSepratorLength
                //primarySeprator.isVisible = false
                secondarySeprator.length = StatusBarController.hiddenSepratorLength
                //secondarySeprator.isVisible = false
                masterToggle.button?.image = Assets.expandImage
                
            case .partialExpand:
                primarySeprator.length = StatusBarController.hiddenSepratorLength
                //primarySeprator.isVisible = false
                secondarySeprator.length = StatusBarController.expandedSeperatorLength
                //secondarySeprator.isVisible = true
                masterToggle.button?.image = Assets.expandImage
                
            case .collapsed:
                primarySeprator.length = StatusBarController.expandedSeperatorLength
                //primarySeprator.isVisible = true
                secondarySeprator.length = StatusBarController.expandedSeperatorLength
                //secondarySeprator.isVisible = true
                masterToggle.button?.image = Assets.collapseImage
                
            }
        }
        lock.unlock()
    }

    private static func adjustMenuBar () {
        
        //TODO: do not deactivate if preference window is shown
        let lock = instance.updateLock
        
        lock.lock(before: Date(timeIntervalSinceNow: 1))
        if !Preferences.isUsingFullStatusBar {
            NSApp.setActivationPolicy(.accessory)
        }
        else {
            let shouldActiveIgnoringOtherApp = !Util.hasFullScreenWindow()
            switch (Preferences.isEditMode, Preferences.statusBarPolicy) {
                
            case (true, _), (_, .partialExpand), (_, .fullExpand):
                if Preferences.isUsingFullStatusBar {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: shouldActiveIgnoringOtherApp)
                }
            case (false, .collapsed):
                NSApp.setActivationPolicy(.accessory)
                NSApp.deactivate()
            }
        }
        lock.unlock()
    }
    
    
    /*
     SYSTEM BUG?
     SOMEHOW WHEN SETTING isVisible PROPERTY OF A NSStatusBarItem, THE APP CRASHES FOR BAD ACCESS.
     => set isVisible will trigger the notification that triggers the observer, causing infinite recursion on this procedure
     => set isVisible to false will discard its location on status bar
     */
    
    /* === TRASH ===
    func showHideSeparatorsAndAlwayHideArea() {
        NSLog("\(Preferences.areSeparatorsHidden)")
        Preferences.areSeparatorsHidden ? showSeparators() : hideSeparators()
        
        if isCollapsed {expandMenubar()}
    }
    
    private func showSeparators() {
        Preferences.areSeparatorsHidden = false
        
        if !isCollapsed {
            primarySeprator.length = normalSepratorLength
        }
        btnAlwaysHidden?.length = btnAlwaysHiddenLength
    }
    
    private func hideSeparators() {
        guard isBtnAlwaysHiddenValidPosition else {return}
        
        Preferences.areSeparatorsHidden = true
        
        if !isCollapsed {
            primarySeprator.length = normalSepratorLength
        }
        btnAlwaysHidden?.length = btnAlwaysHiddenEnableExpandCollapseLength
    }
    
    
    
    func expandCollapseIfNeeded() {
        //prevented rapid click cause icon show many in Dock
        if isToggle {return}
        isToggle = true
        isCollapsed ? expandMenubar() : collapseMenuBar()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isToggle = false
        }
    }
    
    private func collapseMenuBar() {
        guard isprimarySepratorValidPosition && !isCollapsed else {
            autoCollapseIfNeeded()
            return
        }
        
        primarySeprator.length = expandedSeperatorLength
        if let button = masterToggle.button {
            button.image = Assets.expandImage
        }
        if Preferences.useFullStatusBarOnExpandEnabled {
            NSApp.setActivationPolicy(.accessory)
            NSApp.deactivate()
        }
    }
    private func expandMenubar() {
        guard isCollapsed else {return}
        primarySeprator.length = normalSepratorLength
        if let button = masterToggle.button {
            button.image = Assets.collapseImage
        }
        autoCollapseIfNeeded()
        
        if Preferences.useFullStatusBarOnExpandEnabled {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    private func autoCollapseIfNeeded() {
        guard Preferences.isAutoHide else {return}
        guard !isCollapsed else { return }
        
        startTimerToAutoHide()
    }
    
    private func startTimerToAutoHide() {
        //autoCollapseTimer.invalidate()
    }
    */
    
    /*
    private func updateAutoCollapseMenuTitle() {
        guard let toggleAutoHideItem = primarySeprator.menu?.item(withTag: 1) else { return }
        if Preferences.isAutoHide {
            toggleAutoHideItem.title = "Disable Auto Collapse".localized
        } else {
            toggleAutoHideItem.title = "Enable Auto Collapse".localized
        }
    }
    */
     
    @objc func updateAutoHide() {
        //updateAutoCollapseMenuTitle()
        //autoCollapseIfNeeded()
    }
    

    
    @objc func toggleAutoHide() {
        Preferences.isAutoHide.toggle()
    }
}

//MARK: - Alway hide feature
/*
extension StatusBarController {
    private func setupAlwayHideStatusBar() {
        NotificationCenter.default.addObserver(self, selector: #selector(toggleStatusBarIfNeeded), name: UserDefaults.didChangeNotification, object: nil)
        //NotificationCenter.default.addObserver(self, selector: #selector(toggleStatusBarIfNeeded), name: .alwayHideToggle, object: nil)
        toggleStatusBarIfNeeded()
    }
    @objc private func toggleStatusBarIfNeeded() {
        if Preferences.alwaysHiddenSectionEnabled {
            NSLog("FIXME: Always Hidden func bypassed.")
            return;
            /*
            btnAlwaysHidden =  NSStatusBar.system.statusItem(withLength: 20)
            if let button = btnAlwaysHidden?.button {
                button.image = imgIconLine
                button.appearsDisabled = true
            }
            btnAlwaysHidden?.autosaveName = "hiddenbar_terminate";
            */
        }else {
            //btnAlwaysHidden = nil
        }
    }
}
*/


/*
 let a = NSStatusBar.system.thickness
 let b = masterToggle.button!.window!.convertPoint(toScreen: masterToggle.button!.bounds.origin)
 
 masterToggle.button!.draw(NSRect(x: a.minX, y: a.minY, width: a.width, height: a.height))
 NSLog("\(a), \(b)")
 
StatusBarMenuManager.getContextMenu().popUp(positioning: nil, at: CGPoint(x:(masterToggle.button!.frame.minX), y:(masterToggle.button!.frame.minY)), in: masterToggle.button!.superview!.superview!.superview)
 
 StatusBarMenuManager.getContextMenu().popUp(positioning: nil, at: .init(x: sender.bounds.minX, y: sender.bounds.maxY), in: sender)
 
 */
