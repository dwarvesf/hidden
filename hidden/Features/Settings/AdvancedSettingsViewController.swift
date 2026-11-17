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

    /// English title of a "Right-click on the arrow" choice, also its Localizable.strings key.
    static func rightClickTitle(for choice: RightClickAction) -> String {
        switch choice {
        case .showMenu: return "Show menu"
        case .showAlwaysHidden: return "Show always-hidden icons"
        }
    }

    /// Where the action right-click does not do went.
    static func rightClickCaption(for choice: RightClickAction) -> String {
        switch choice {
        case .showMenu: return "Option-click the arrow to see always-hidden icons.".localized
        case .showAlwaysHidden: return "Option-right-click the arrow to open the menu.".localized
        }
    }

    override func buildForm() {
        let showWindow = boundSwitch(UserDefaults.Key.isShowPreference, read: { Preferences.isShowPreference },
                                     write: { Preferences.isShowPreference = $0 })

        let fullBar = boundSwitch(UserDefaults.Key.useFullStatusBarOnExpandEnabled,
                                  read: { Preferences.useFullStatusBarOnExpandEnabled },
                                  write: { Preferences.useFullStatusBarOnExpandEnabled = $0 })
        var rows = [SettingsForm.row("Show this window when Hidden Bar opens".localized, control: showWindow),
                    SettingsForm.row("Make room for icons while they are shown".localized,
                                          caption: "Hides the menus of the app you are using while hidden icons are shown, so more icons fit.".localized,
                                          control: fullBar),
                    rightClickRow()]
        // The notch row only where a notch exists and macOS can put icons behind it.
        if context.showsNotchOverflow {
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
            let row = SettingsForm.row("Pause hiding while macOS shows Now Playing, Focus and similar items".localized,
                                       caption: " ", control: pause)
            macOSAlsoHidesCaption = Self.captionLabel(in: row)
            rows.append(row)
            onRefresh { [weak self] in self?.refreshMacOSAlsoHides() }

            let pinned = boundSwitch(UserDefaults.Key.pinnedSectionsEnabled,
                                     read: { Preferences.pinnedSectionsEnabled },
                                     write: { Preferences.pinnedSectionsEnabled = $0 })
            rows.append(SettingsForm.row("Pinned sections (beta)".localized,
                                         caption: "Keeps each app in the section you pick in Icons, also after it restarts. Applies at the next collapse.".localized,
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

    // A popup, not a switch: it names both choices, like the menu it replaces.
    private func rightClickRow() -> NSView {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.controlSize = .small
        for choice in RightClickAction.allCases {
            popup.addItem(withTitle: Self.rightClickTitle(for: choice).localized)
        }
        popup.identifier = NSUserInterfaceItemIdentifier(UserDefaults.Key.rightClickAction)
        popup.target = self
        popup.action = #selector(rightClickPicked(_:))
        let row = SettingsForm.row("Right-click on the arrow".localized,
                                   caption: Self.rightClickCaption(for: Preferences.rightClickAction), control: popup)
        let caption = (row.subviews.first { $0 is NSStackView } as? NSStackView)?.arrangedSubviews.last as? NSTextField
        onRefresh { [weak popup, weak caption] in
            let choice = Preferences.rightClickAction
            popup?.selectItem(at: RightClickAction.allCases.firstIndex(of: choice) ?? 0)
            caption?.stringValue = Self.rightClickCaption(for: choice)
        }
        return row
    }

    @objc private func rightClickPicked(_ sender: NSPopUpButton) {
        guard RightClickAction.allCases.indices.contains(sender.indexOfSelectedItem) else { return }
        Preferences.rightClickAction = RightClickAction.allCases[sender.indexOfSelectedItem]
    }

    private func refreshMacOSAlsoHides() {
        let names = NativeVisibilityEngine.knownUnkeepableSystemItems.map(NativeVisibilityEngine.displayName(ofSystemItem:))
            + NativeVisibilityEngine.knownUnkeepableApps
        let help = "macOS 27 hides these items whenever an app hides icons. While one shows, Hidden Bar hides nothing.".localized
        macOSAlsoHidesCaption?.stringValue = names.isEmpty
            ? help
            : help + " " + String(format: "Seen on this Mac: %@.".localized, names.joined(separator: ", "))
    }

    private static func captionLabel(in row: NSView) -> NSTextField? {
        func all(_ view: NSView) -> [NSView] { view.subviews + view.subviews.flatMap(all) }
        return all(row).compactMap { $0 as? NSTextField }.first { $0.stringValue == " " }
    }
}
