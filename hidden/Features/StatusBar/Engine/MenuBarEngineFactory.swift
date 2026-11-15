//
//  MenuBarEngineFactory.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import AppKit

// The single place that picks a hiding mechanism for the running OS.
enum MenuBarEngineFactory {
    // True when the running build and OS hide icons natively (the arrow is the
    // boundary), false when the separator-length engine runs.
    static func usesNativeEngine(osMajorVersion: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion) -> Bool {
        #if HIDDENBAR_NATIVE_VISIBILITY
        return osMajorVersion >= 27
        #else
        return false
        #endif
    }

    static func make(items: MenuBarItemProvider) -> MenuBarEngine {
        // macOS 27 ejects an inflated separator from the menu bar (#360). The
        // direct build hides natively there instead. The App Store build cannot:
        // the sandbox blocks the Accessibility reads that locate the sections.
        #if HIDDENBAR_NATIVE_VISIBILITY
        if usesNativeEngine() {
            return NativeVisibilityEngine(items: items,
                                          captureActivity: CaptureActivityMonitor(),
                                          runsFromApplicationsFolder: runsFromApplicationsFolder,
                                          pausesHidingForUnkeepableItems: { Preferences.pauseHidingForUnkeepableItems },
                                          expandsWhenCaptureStarts: { Preferences.showWholeBarWhenCaptureStarts },
                                          sectionMemory: UserDefaultsSectionMemory(),
                                          workspaceNotifications: NSWorkspace.shared.notificationCenter,
                                          pinnedSections: UserDefaultsPinnedSections(),
                                          pinsSections: { Preferences.pinnedSectionsEnabled },
                                          agentLaunches: AgentLaunchNotifications(isActive: {
                                              AgentLaunchNotifications.isActive(pinnedSectionsEnabled: Preferences.pinnedSectionsEnabled)
                                          }))
        }
        #endif
        return LegacyLengthEngine(items: items)
    }

    // Debug builds run from build folders, so the check is off there unless a
    // test hook turns it on. Settings reads it too, for its status card.
    static func runsFromApplicationsFolder() -> Bool {
        #if DEBUG
        if !NativeVisibilityEngine.debugChecksInstallLocation { return true }
        #endif
        return NativeVisibilityEngine.isInApplicationsFolder(Bundle.main.bundleURL)
    }

    // Native hiding has no separator and needs the Accessibility permission.
    static var usesNativeVisibility: Bool { usesNativeEngine() }
}

extension AccessibilityPermission {
    static let shared = AccessibilityPermission(needsPermission: MenuBarEngineFactory.usesNativeVisibility)
}
