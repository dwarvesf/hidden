//
//  UserDefault+Extension.swift
//  Hidden Bar
//
//  Created by phucld on 12/18/19.
//  Copyright © 2019 Console Labs. All rights reserved.
//

import Foundation

extension UserDefaults {
    enum Key {
        static let globalKey = "globalKey"
        static let findHiddenIconShortcut = "findHiddenIconShortcut"
        static let numberOfSecondForAutoHide = "numberOfSecondForAutoHide"
        static let isAutoStart = "isAutoStart"
        static let isAutoHide = "isAutoHide"
        static let isShowPreference = "isShowPreferences"
        static let areSeparatorsHidden = "areSeparatorsHidden"
        static let alwaysHiddenSectionEnabled = "alwaysHiddenSectionEnabled"
        static let useFullStatusBarOnExpandEnabled = "useFullStatusBarOnExpandEnabled"
        static let stealthExpandIconEnabled = "stealthExpandIconEnabled"
        static let arrowStyle = "arrowStyle"
        static let hoverToExpand = "hoverToExpand"
        static let revealOnScrollEnabled = "revealOnScrollEnabled"
        static let revealOnEmptyClickEnabled = "revealOnEmptyClickEnabled"
        static let revealOnShakeEnabled = "revealOnShakeEnabled"
        static let notchOverflowEnabled = "notchOverflowEnabled"
        static let pauseHidingForUnkeepableItems = "pauseHidingForUnkeepableItems"
        static let showWholeBarWhenCaptureStarts = "showWholeBarWhenCaptureStarts"
        static let pinnedSectionsEnabled = "pinnedSectionsEnabled"
        static let newAppDefaultSection = "newAppDefaultSection"
        static let presentationAutoMirrorEnabled = "presentationAutoMirrorEnabled"
        static let presentationSensitiveApps = "presentationSensitiveApps"
        static let presentationShortcut = "presentationShortcut"
        static let rightClickAction = "rightClickAction"
        // Internal: not user-facing, so not in the App Store import whitelist.
        static let menuBarCatalogFirstSeen = "menuBarCatalogFirstSeen"
        static let arrivalsPending = "arrivalsPending"
        static let presentationModeActive = "presentationModeActive"
        static let presentationTipShown = "presentationTipShown"
    }
}
