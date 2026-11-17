//
//  SettingsModel.swift
//  Hidden Bar
//
//  Copyright © 2026 Console Labs. All rights reserved.
//

import Foundation

// The decisions behind the Settings window, kept free of AppKit so both test
// bundles can check them: which build this is, which panes it shows, what the
// status card says, and how the auto-hide popup maps onto the stored prefs.

enum SettingsBuild: Equatable {
    /// GitHub / Homebrew build: Sparkle updates, native hiding on macOS 27.
    case direct
    /// Mac App Store build: sandboxed, separator engine only.
    case appStore

    static var current: SettingsBuild {
        #if HIDDENBAR_NATIVE_VISIBILITY
        return .direct
        #else
        return .appStore
        #endif
    }

    /// The native engine runs only in the direct build on macOS 27 and later.
    func usesNativeEngine(osMajorVersion: Int) -> Bool {
        self == .direct && osMajorVersion >= 27
    }
}

enum SettingsTab: String, CaseIterable {
    case general
    case menuBarApps
    case appearance
    case advanced
    case about

    /// English text, which is also the Localizable.strings key.
    var titleKey: String {
        switch self {
        case .general: return "General"
        case .menuBarApps: return "Icons"
        case .appearance: return "Appearance"
        case .advanced: return "Advanced"
        case .about: return "About"
        }
    }


    /// Icons lists the pinned sections, which only the native engine
    /// has; the pane appears once that feature registers its content.
    static func visibleTabs(build: SettingsBuild, osMajorVersion: Int, menuBarAppsAvailable: Bool) -> [SettingsTab] {
        let showsApps = menuBarAppsAvailable && build.usesNativeEngine(osMajorVersion: osMajorVersion)
        return allCases.filter { $0 != .menuBarApps || showsApps }
    }
}

/// The card at the top of General. One state at a time, most blocking first.
enum SettingsStatus: Equatable {
    case working
    case needsAccessibility
    case outsideApplications
    case appStoreOnMacOS27

    static func resolve(build: SettingsBuild, osMajorVersion: Int,
                        runsFromApplicationsFolder: Bool, accessibilityMissing: Bool) -> SettingsStatus {
        guard osMajorVersion >= 27 else { return .working }
        if build == .appStore { return .appStoreOnMacOS27 }
        // Outside /Applications macOS 27 hides nothing even with the permission,
        // and moving the app can reset the grant, so the move comes first.
        if !runsFromApplicationsFolder { return .outsideApplications }
        if accessibilityMissing { return .needsAccessibility }
        return .working
    }

    var isWarning: Bool { self != .working }
}

/// What marks the edge between hidden and shown icons in the preview strip.
enum PreviewBoundary: Equatable {
    /// macOS 27 direct build: the arrow itself.
    case arrow
    /// Separator engine: the "|" item just left of the arrow.
    case separator

    static func forEngine(native: Bool) -> PreviewBoundary {
        native ? .arrow : .separator
    }
}

/// One popup for the old "Automatically hide icon after" checkbox and its
/// delay popup. "Never" turns isAutoHide off and keeps the stored delay, so the
/// menu's "Enable Auto Collapse" still comes back with the delay the user had.
enum AutoHideChoice: Equatable {
    case never
    case after(seconds: Double)

    static let delays: [Double] = [5, 10, 15, 30, 60]
    static let all: [AutoHideChoice] = [.never] + delays.map { .after(seconds: $0) }

    init(isAutoHide: Bool, seconds: Double) {
        guard isAutoHide else { self = .never; return }
        // Same fallback as the old popup: an unknown delay reads as 5 seconds.
        self = .after(seconds: Self.delays.contains(seconds) ? seconds : Self.delays[0])
    }

    var index: Int { Self.all.firstIndex(of: self) ?? 0 }

    var titleKey: String {
        switch self {
        case .never: return "Never"
        case .after(let seconds) where seconds >= 60: return "After 1 minute"
        case .after: return "After %d seconds"
        }
    }

    /// The prefs to write: isAutoHide, and the delay when one was picked.
    var stored: (isAutoHide: Bool, seconds: Double?) {
        switch self {
        case .never: return (false, nil)
        case .after(let seconds): return (true, seconds)
        }
    }
}
