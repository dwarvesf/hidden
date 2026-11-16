//
//  Preferences.swift
//  Hidden Bar
//
//  Created by phucld on 12/18/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import Foundation

enum Preferences {
    
    static var globalKey: GlobalKeybindPreferences? {
        get {
            guard let data = UserDefaults.standard.value(forKey: UserDefaults.Key.globalKey) as? Data else { return nil }
            return try? JSONDecoder().decode(GlobalKeybindPreferences.self, from: data)
        }
        
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: UserDefaults.Key.globalKey)
            
            NotificationCenter.default.post(Notification(name: .prefsChanged))
        }
    }
    
    /// The global shortcut that opens the type-to-find palette. Unset means the
    /// feature is off; the registry binds it, so setting it needs no other call.
    static var findHiddenIconShortcut: GlobalKeybindPreferences? {
        get {
            guard let data = UserDefaults.standard.data(forKey: UserDefaults.Key.findHiddenIconShortcut) else { return nil }
            return try? JSONDecoder().decode(GlobalKeybindPreferences.self, from: data)
        }

        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: UserDefaults.Key.findHiddenIconShortcut)
            } else {
                UserDefaults.standard.removeObject(forKey: UserDefaults.Key.findHiddenIconShortcut)
            }
            NotificationCenter.default.post(Notification(name: .prefsChanged))
        }
    }

    static var isAutoStart: Bool {
        get {
            return UserDefaults.standard.bool(forKey: UserDefaults.Key.isAutoStart)
        }
        
        set {
            // Apply first, then persist the outcome: on failure the stored value
            // stays at the previous state so the prefs checkbox shows reality
            // instead of the intent.
            let applied = Util.setUpAutoStart(isAutoStart: newValue)
            UserDefaults.standard.set(applied ? newValue : isAutoStart, forKey: UserDefaults.Key.isAutoStart)

            NotificationCenter.default.post(Notification(name: .prefsChanged))
        }
    }
    
    static var numberOfSecondForAutoHide: Double {
        get {
            UserDefaults.standard.double(forKey: UserDefaults.Key.numberOfSecondForAutoHide)
        }
        
        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.numberOfSecondForAutoHide)
            
            NotificationCenter.default.post(Notification(name: .prefsChanged))
        }
    }
    
    static var isAutoHide: Bool {
        get {
            UserDefaults.standard.bool(forKey: UserDefaults.Key.isAutoHide)
        }
        
        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.isAutoHide)
            
            NotificationCenter.default.post(Notification(name: .prefsChanged))
        }
    }
    
    static var isShowPreference: Bool {
        get {
            UserDefaults.standard.bool(forKey: UserDefaults.Key.isShowPreference)
        }
        
        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.isShowPreference)
            
            NotificationCenter.default.post(Notification(name: .prefsChanged))
        }
    }
    
    static var areSeparatorsHidden: Bool {
        get {
            UserDefaults.standard.bool(forKey: UserDefaults.Key.areSeparatorsHidden)
        }
        
        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.areSeparatorsHidden)
        }
    }
    
    static var alwaysHiddenSectionEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: UserDefaults.Key.alwaysHiddenSectionEnabled)
        }
        
        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.alwaysHiddenSectionEnabled)
            NotificationCenter.default.post(Notification(name: .alwayHideToggle))
        }
    }
    
    static var hoverToExpand: Bool {
        get {
            UserDefaults.standard.bool(forKey: UserDefaults.Key.hoverToExpand)
        }

        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.hoverToExpand)
            NotificationCenter.default.post(Notification(name: .prefsChanged))
        }
    }

    // Reveal without aiming at the arrow: each gesture is its own opt-in switch.
    // Scroll down on the menu bar shows the hidden icons, scroll up hides them.
    static var revealOnScrollEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: UserDefaults.Key.revealOnScrollEnabled)
        }

        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.revealOnScrollEnabled)
            NotificationCenter.default.post(Notification(name: .prefsChanged))
        }
    }

    // A click on empty menu bar space shows them. Needs Accessibility to tell
    // empty space from an icon, so the direct build only.
    static var revealOnEmptyClickEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: UserDefaults.Key.revealOnEmptyClickEnabled)
        }

        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.revealOnEmptyClickEnabled)
            NotificationCenter.default.post(Notification(name: .prefsChanged))
        }
    }

    // Three quick side-to-side moves of the pointer inside the menu bar show them.
    static var revealOnShakeEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: UserDefaults.Key.revealOnShakeEnabled)
        }

        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.revealOnShakeEnabled)
            NotificationCenter.default.post(Notification(name: .prefsChanged))
        }
    }

    // Presentation mode turns itself on while a display is mirrored. Off by default.
    static var presentationAutoMirrorEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: UserDefaults.Key.presentationAutoMirrorEnabled)
        }

        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.presentationAutoMirrorEnabled)
            NotificationCenter.default.post(Notification(name: .prefsChanged))
        }
    }

    // Apps that stay hidden while presentation mode is on, even when the arrow
    // is clicked. Stored as a dictionary [bundle id: true].
    static var presentationSensitiveApps: Set<String> {
        get {
            let stored = UserDefaults.standard.dictionary(forKey: UserDefaults.Key.presentationSensitiveApps) ?? [:]
            return Set(stored.filter { ($0.value as? Bool) == true }.keys)
        }

        set {
            let stored = Dictionary(uniqueKeysWithValues: newValue.map { ($0, true) })
            UserDefaults.standard.set(stored, forKey: UserDefaults.Key.presentationSensitiveApps)
            NotificationCenter.default.post(Notification(name: .prefsChanged))
        }
    }

    // Internal: whether presentation mode is on right now, for scripts and the
    // debug state. Never read back to resume a session: a manual start does not
    // survive a relaunch, so a crash never re-hides the bar on its own.
    static var presentationModeActive: Bool {
        get {
            UserDefaults.standard.bool(forKey: UserDefaults.Key.presentationModeActive)
        }

        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.presentationModeActive)
        }
    }

    // Internal: the first-start tip under the Presenting capsule was shown once.
    // Not a Settings row and not imported from the App Store build.
    static var presentationTipShown: Bool {
        get {
            UserDefaults.standard.bool(forKey: UserDefaults.Key.presentationTipShown)
        }

        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.presentationTipShown)
        }
    }

    static var useFullStatusBarOnExpandEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: UserDefaults.Key.useFullStatusBarOnExpandEnabled)
        }

        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.useFullStatusBarOnExpandEnabled)
            NotificationCenter.default.post(Notification(name: .useFullStatusBarToggle))
        }
    }

    // Fades the arrow to near invisible while the bar is collapsed, so the app
    // is hard to spot in the menu bar (issue #173). Off by default.
    static var stealthExpandIconEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: UserDefaults.Key.stealthExpandIconEnabled)
        }

        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.stealthExpandIconEnabled)
            NotificationCenter.default.post(Notification(name: .stealthExpandIconToggle))
        }
    }

    // Which expand/collapse arrow the status item shows (issue #310). Stored as
    // the style's name; anything unreadable reads as the default arrow.
    static var arrowStyle: ArrowStyle {
        get {
            ArrowStyle(storedValue: UserDefaults.standard.string(forKey: UserDefaults.Key.arrowStyle))
        }

        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: UserDefaults.Key.arrowStyle)
            NotificationCenter.default.post(Notification(name: .arrowStyleChanged))
        }
    }

    static var notchOverflowEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: UserDefaults.Key.notchOverflowEnabled)
        }

        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.notchOverflowEnabled)
        }
    }

    // macOS 27, direct build: keep every icon shown while one right of the arrow
    // cannot be kept visible by the allow-list. Off by default.
    static var pauseHidingForUnkeepableItems: Bool {
        get {
            UserDefaults.standard.bool(forKey: UserDefaults.Key.pauseHidingForUnkeepableItems)
        }

        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.pauseHidingForUnkeepableItems)
            NotificationCenter.default.post(Notification(name: .prefsChanged))
        }
    }

    // macOS 27, direct build: expand the bar once when a microphone or camera
    // turns on, so the capsule naming the app shows. On by default.
    static var showWholeBarWhenCaptureStarts: Bool {
        get {
            UserDefaults.standard.bool(forKey: UserDefaults.Key.showWholeBarWhenCaptureStarts)
        }

        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.showWholeBarWhenCaptureStarts)
            NotificationCenter.default.post(Notification(name: .prefsChanged))
        }
    }

    // macOS 27, direct build: the section table decides where each app goes
    // (beta). On by default; off is v1.11.2's position-based sections.
    static var pinnedSectionsEnabled: Bool {
        get {
            UserDefaults.standard.object(forKey: UserDefaults.Key.pinnedSectionsEnabled) as? Bool ?? true
        }

        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.pinnedSectionsEnabled)
            NotificationCenter.default.post(Notification(name: .prefsChanged))
        }
    }

    // macOS 27, direct build: what happens to an app that adds its first icon.
    // Show It (the 1.12 behavior) unless the user picks otherwise.
    static var newAppDefaultSection: NewAppDefault {
        get {
            NewAppDefault(rawValue: UserDefaults.standard.object(forKey: UserDefaults.Key.newAppDefaultSection) as? Int ?? NewAppDefault.show.rawValue) ?? .show
        }

        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: UserDefaults.Key.newAppDefaultSection)
            NotificationCenter.default.post(Notification(name: .prefsChanged))
        }
    }
}
