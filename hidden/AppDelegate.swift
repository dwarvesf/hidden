//
//  AppDelegate.swift
//  vanillaClone
//
//  Created by Thanh Nguyen on 1/24/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import AppKit
import Carbon
import HotKey

@NSApplicationMain

class AppDelegate: NSObject, NSApplicationDelegate{
    
    var statusBarController = StatusBarController()

    var hotKey: HotKey? {
        didSet {
            guard let hotKey = hotKey else { return }

            hotKey.keyDownHandler = { [weak self] in
                self?.statusBarController.expandCollapseIfNeeded()
            }
        }
    }

    // Notch overflow hotkey: Cmd+Shift+B
    var notchOverflowHotKey: HotKey?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        setupAutoStartApp()
        registerDefaultValues()
        setupHotKey()
        openPreferencesIfNeeded()
        detectLTRLang()
        statusBarController.setupNotchOverflow()
        setupNotchOverflowHotKey()
    }

    func setupNotchOverflowHotKey() {
        guard NotchOverflowController.hasNotch else { return }
        // Cmd+Shift+B (keyCode 11 = B)
        let carbonMods = UInt32(cmdKey | shiftKey)
        notchOverflowHotKey = HotKey(keyCombo: KeyCombo(carbonKeyCode: 11, carbonModifiers: carbonMods))
        notchOverflowHotKey?.keyDownHandler = { [weak self] in
            self?.statusBarController.notchOverflowController.triggerOverflow()
        }
    }
    
    func openPreferencesIfNeeded() {
        if Preferences.isShowPreference {
            Util.showPrefWindow()
        }
    }
    
    func setupAutoStartApp() {
        Util.setUpAutoStart(isAutoStart: Preferences.isAutoStart)
    }
    
    func registerDefaultValues() {
         UserDefaults.standard.register(defaults: [
            UserDefaults.Key.isAutoStart: false,
            UserDefaults.Key.isShowPreference: true,
            UserDefaults.Key.isAutoHide: true,
            UserDefaults.Key.numberOfSecondForAutoHide: 10.0,
            UserDefaults.Key.areSeparatorsHidden: false,
            UserDefaults.Key.alwaysHiddenSectionEnabled: false,
            UserDefaults.Key.notchOverflowEnabled: true
         ])
    }
    
    func setupHotKey() {
        guard let globalKey = Preferences.globalKey else {return}
        hotKey = HotKey(keyCombo: KeyCombo(carbonKeyCode: globalKey.keyCode, carbonModifiers: globalKey.carbonFlags))
    }
    
    func detectLTRLang() {
        // Languages like Arabic uses right to left (RTL) writing direction,
        // so some behavier of the app needs to be changed in these cases
        
        Constant.isUsingLTRLanguage = (NSApplication.shared.userInterfaceLayoutDirection == .leftToRight)
    }
   
}
