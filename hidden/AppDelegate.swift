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

    /// Every global shortcut; a feature adds its own with `register(key:handler:)`.
    let hotKeys = HotKeyRegistry.shared

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
        // A test host never starts Sparkle or takes the move and migration
        // offers: they act on the machine's real install.
        guard AppDefaults.allowsHostSideEffects else { return }
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
        hotKeys.reload()
        for name in Self.importedPreferenceNotifications {
            NotificationCenter.default.post(name: name, object: nil)
        }
    }

    /// What an import tells the rest of the app. The pinned-sections switch and
    /// table are read through their own notice, not `.prefsChanged`.
    static let importedPreferenceNotifications: [Notification.Name] = [
        .prefsChanged, .pinnedSectionsChanged, .alwayHideToggle, .useFullStatusBarToggle,
        .stealthExpandIconToggle, .arrowStyleChanged,
    ]
    #endif

    /// Hidden Bar is a menu bar utility with no visible window, so launching it a
    /// second time looks like a no-op while silently spawning a duplicate instance.
    /// If another instance with the same bundle ID is already running, activate it
    /// and terminate this one instead.
    private func ensureSingleInstance() -> Bool {
        guard AutoStart.shouldEnforceSingleInstance() else { return true }
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
        LegacyLoginItem.migrateUnlessTesting(autoStart: Preferences.isAutoStart)
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
        AppDefaults.store.register(defaults: AppDelegate.defaultPreferenceValues)
    }
    
    func setupHotKey() {
        hotKeys.register(key: UserDefaults.Key.globalKey, title: "Show or hide icons".localized) { [weak self] in
            self?.statusBarController.expandCollapseIfNeeded()
        }
        #if HIDDENBAR_NATIVE_VISIBILITY
        Self.registerNativeEngineHotKeys(in: hotKeys, usesNativeEngine: MenuBarEngineFactory.usesNativeEngine(),
                                         togglePalette: { [weak self] in self?.statusBarController.togglePalette() },
                                         togglePresentation: { [weak self] in self?.statusBarController.togglePresentationMode() })
        #endif
    }

    #if HIDDENBAR_NATIVE_VISIBILITY
    /// The palette and presentation shortcuts exist only where the native engine
    /// runs. Both are unset by default, so the features are off until recorded.
    static func registerNativeEngineHotKeys(in hotKeys: HotKeyRegistry, usesNativeEngine: Bool,
                                            togglePalette: @escaping () -> Void,
                                            togglePresentation: @escaping () -> Void) {
        guard usesNativeEngine else { return }
        hotKeys.register(key: UserDefaults.Key.findHiddenIconShortcut, title: "Find a hidden icon".localized,
                         handler: togglePalette)
        hotKeys.register(key: UserDefaults.Key.presentationShortcut, title: "Presentation mode".localized,
                         handler: togglePresentation)
    }
    #endif
    
    func detectLTRLang() {
        // Languages like Arabic uses right to left (RTL) writing direction,
        // so some behavier of the app needs to be changed in these cases
        
        Constant.isUsingLTRLanguage = (NSApplication.shared.userInterfaceLayoutDirection == .leftToRight)
    }
   
}

extension HotKeyRegistry {
    /// The app's registry, bound to the HotKey library (a Carbon hot key each).
    static let shared = HotKeyRegistry { combo, handler in
        let hotKey = HotKey(keyCombo: KeyCombo(carbonKeyCode: combo.keyCode, carbonModifiers: combo.carbonFlags))
        hotKey.keyDownHandler = handler
        return hotKey
    }
}
