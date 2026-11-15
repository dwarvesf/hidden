//
//  AdvancedSettingsViewController.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import AppKit

/// Settings most people never change.
final class AdvancedSettingsViewController: SettingsPaneController {
    private var macOSAlsoHidesCaption: NSTextField?

    override func buildForm() {
        let showWindow = boundSwitch(UserDefaults.Key.isShowPreference, read: { Preferences.isShowPreference },
                                     write: { Preferences.isShowPreference = $0 })

        let fullBar = boundSwitch(UserDefaults.Key.useFullStatusBarOnExpandEnabled,
                                  read: { Preferences.useFullStatusBarOnExpandEnabled },
                                  write: { Preferences.useFullStatusBarOnExpandEnabled = $0 })
        var rows = [SettingsForm.row("Show this window when Hidden Bar opens".localized, control: showWindow),
                    SettingsForm.row("Make room for icons while they are shown".localized,
                                          caption: "Hides the menus of the app you are using while hidden icons are shown, so more icons fit.".localized,
                                          control: fullBar)]
        // The notch row only where a notch exists, as before.
        if context.hasNotch {
            let notch = boundSwitch(UserDefaults.Key.notchOverflowEnabled, read: { Preferences.notchOverflowEnabled },
                                    write: { Preferences.notchOverflowEnabled = $0 })
            rows.append(SettingsForm.row("Reach icons behind the camera notch".localized,
                                              caption: "Right-click the arrow to list icons the notch covers.".localized,
                                              control: notch))
        }

        if context.usesNativeEngine {
            let pause = boundSwitch(UserDefaults.Key.pauseHidingForUnkeepableItems,
                                    read: { Preferences.pauseHidingForUnkeepableItems },
                                    write: { Preferences.pauseHidingForUnkeepableItems = $0 })
            let row = SettingsForm.row("Show all icons while macOS hides one right of the arrow".localized,
                                       caption: " ", control: pause)
            macOSAlsoHidesCaption = Self.captionLabel(in: row)
            rows.append(row)
            onRefresh { [weak self] in self?.refreshMacOSAlsoHides() }

            let pinned = boundSwitch(UserDefaults.Key.pinnedSectionsEnabled,
                                     read: { Preferences.pinnedSectionsEnabled },
                                     write: { Preferences.pinnedSectionsEnabled = $0 })
            rows.append(SettingsForm.row("Pinned sections (beta)".localized,
                                         caption: "Keeps each app in the section you pick in Menu Bar Apps, also after it restarts. Applies at the next collapse.".localized,
                                         control: pinned))
        }

        let method = NSTextField(labelWithString: (context.usesNativeEngine ? "macOS 27 visibility" : "Separator").localized)
        method.textColor = .secondaryLabelColor
        rows.append(
            SettingsForm.row("Hiding method".localized,
                             caption: (context.usesNativeEngine
                                       ? "The arrow is the edge. Picked for your macOS version."
                                       : "The | separator is the edge. Picked for your macOS version.").localized,
                             control: method))
        // One group: every row here is set once, if ever.
        addSection(nil, rows: rows)
        refreshAll()
    }

    private func refreshMacOSAlsoHides() {
        let names = NativeVisibilityEngine.knownUnkeepableSystemItems.map(NativeVisibilityEngine.displayName(ofSystemItem:))
        macOSAlsoHidesCaption?.stringValue = names.isEmpty
            ? "Some macOS items, such as Focus or Now Playing, can't stay shown. This keeps every icon shown while one of them is right of the arrow.".localized
            : String(format: "macOS 27 also hides: %@".localized, names.joined(separator: ", "))
    }

    private static func captionLabel(in row: NSView) -> NSTextField? {
        func all(_ view: NSView) -> [NSView] { view.subviews + view.subviews.flatMap(all) }
        return all(row).compactMap { $0 as? NSTextField }.first { $0.stringValue == " " }
    }
}
