//
//  AppDelegate.swift
//  vanillaClone
//
//  Created by Thanh Nguyen on 1/24/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import AppKit
import HotKey
import ServiceManagement

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

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        #if DEBUG
        if SettingsSnapshot.runIfRequested() { return }
        #endif
        guard ensureSingleInstance() else { return }
        #if HIDDENBAR_NATIVE_VISIBILITY
        // Pinned sections (beta) fill the Settings tab the native engine has.
        if MenuBarEngineFactory.usesNativeEngine() {
            MenuBarAppsPane.makeViewController = { MenuBarAppsSettingsViewController(context: .live) }
        }
        #endif
        setupAutoStartApp()
        registerDefaultValues()
        setupHotKey()
        openPreferencesIfNeeded()
        detectLTRLang()
        #if HIDDENBAR_SPARKLE
        _ = UpdateController.shared // starts the updater and its scheduled checks
        #endif
        #if !HIDDENBAR_NATIVE_VISIBILITY
        MacOS27Notice.shared.showAtLaunchIfNeeded()
        #else
        AppStoreMigration.shared.runAtLaunchIfNeeded { [weak self] in
            self?.applyImportedPreferences()
        }
        #endif
    }

    #if HIDDENBAR_NATIVE_VISIBILITY
    /// Settings imported from the App Store build were written straight to
    /// UserDefaults; apply the ones with side effects and tell the UI.
    private func applyImportedPreferences() {
        Util.setUpAutoStart(isAutoStart: Preferences.isAutoStart)
        setupHotKey()
        for name: Notification.Name in [.prefsChanged, .alwayHideToggle, .useFullStatusBarToggle,
                                        .stealthExpandIconToggle, .arrowStyleChanged] {
            NotificationCenter.default.post(name: name, object: nil)
        }
    }
    #endif

    /// Hidden Bar is a menu bar utility with no visible window, so launching it a
    /// second time looks like a no-op while silently spawning a duplicate instance.
    /// If another instance with the same bundle ID is already running, activate it
    /// and terminate this one instead.
    private func ensureSingleInstance() -> Bool {
        #if HIDDENBAR_NATIVE_VISIBILITY
        // The direct build asks before quitting an App Store copy that is running.
        return AppStoreMigration.shared.resolveOtherRunningCopy()
        #else
        let current = ProcessInfo.processInfo.processIdentifier
        let existing = NSWorkspace.shared.runningApplications.first {
            guard $0.bundleIdentifier == Bundle.main.bundleIdentifier,
                  $0.processIdentifier != current else { return false }
            #if DEBUG
            // Let a dev build run next to the installed copy; only dedupe
            // relaunches of the same bundle path.
            return $0.bundleURL == Bundle.main.bundleURL
            #else
            return true
            #endif
        }
        guard let existing else { return true }
        existing.activate(options: [.activateAllWindows])
        NSApp.terminate(nil)
        return false
        #endif
    }
    
    func openPreferencesIfNeeded() {
        if Preferences.isShowPreference {
            Util.showPrefWindow()
        }
    }
    
    func setupAutoStartApp() {
        LegacyLoginItem.remove()
        Util.setUpAutoStart(isAutoStart: Preferences.isAutoStart)
    }
    
    // A plain value, separate from the side-effecting `register(defaults:)`
    // call, so the "what are the defaults" behavior is testable without
    // spinning up an AppDelegate (which creates real status bar items).
    static let defaultPreferenceValues: [String: Any] = [
        UserDefaults.Key.isAutoStart: false,
        UserDefaults.Key.isShowPreference: true,
        UserDefaults.Key.isAutoHide: true,
        UserDefaults.Key.numberOfSecondForAutoHide: 10.0,
        UserDefaults.Key.areSeparatorsHidden: false,
        UserDefaults.Key.alwaysHiddenSectionEnabled: false,
        UserDefaults.Key.notchOverflowEnabled: true,
        UserDefaults.Key.stealthExpandIconEnabled: false,
        UserDefaults.Key.arrowStyle: ArrowStyle.default.rawValue,
        UserDefaults.Key.showWholeBarWhenCaptureStarts: true,
        UserDefaults.Key.pinnedSectionsEnabled: true
    ]

    func registerDefaultValues() {
        UserDefaults.standard.register(defaults: AppDelegate.defaultPreferenceValues)
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
