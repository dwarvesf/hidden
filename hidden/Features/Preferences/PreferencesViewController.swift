//
//  ViewController.swift
//  vanillaClone
//
//  Created by Thanh Nguyen on 1/24/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import Cocoa

/// The General pane: status, the menu bar preview, and the everyday settings.
class PreferencesViewController: SettingsPaneController {

    static let hoverToExpandCheckBoxIdentifier = NSUserInterfaceItemIdentifier(UserDefaults.Key.hoverToExpand)
    static let autoHidePopupIdentifier = NSUserInterfaceItemIdentifier(UserDefaults.Key.isAutoHide)

    let statusCard = StatusCardView()
    let preview = MenuBarPreviewView()
    private let previewCaption = SettingsForm.caption("")
    private let autoHidePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let shortcutRecorder = ShortcutRecorderRow(key: UserDefaults.Key.globalKey)
    private(set) var findShortcutRecorder: ShortcutRecorderRow?
    private var accessibilityValue: NSTextField?

    override func buildForm() {
        statusCard.onAction = { [weak self] in self?.statusAction($0) }
        addFullWidth(statusCard)

        previewCaption.alignment = .center
        let previewRow = NSStackView(views: [preview, previewCaption])
        previewRow.orientation = .vertical
        previewRow.spacing = 4
        previewRow.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 9, right: 14)
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.widthAnchor.constraint(equalTo: previewRow.widthAnchor, constant: -28).isActive = true
        previewCaption.widthAnchor.constraint(equalTo: previewRow.widthAnchor, constant: -28).isActive = true
        addSection("Your menu bar".localized, rows: [previewRow])

        let login = boundSwitch(UserDefaults.Key.isAutoStart, read: { Preferences.isAutoStart }) { [weak self] wanted in
            self?.loginChanged(wanted)
        }

        for choice in AutoHideChoice.all {
            let title: String
            if case .after(let seconds) = choice, seconds < 60 {
                title = String(format: choice.titleKey.localized, Int(seconds))
            } else {
                title = choice.titleKey.localized
            }
            autoHidePopup.addItem(withTitle: title)
        }
        autoHidePopup.identifier = Self.autoHidePopupIdentifier
        autoHidePopup.controlSize = .regular
        autoHidePopup.target = self
        autoHidePopup.action = #selector(autoHideChanged(_:))
        onRefresh { [weak self] in
            self?.autoHidePopup.selectItem(at: AutoHideChoice(isAutoHide: Preferences.isAutoHide,
                                                              seconds: Preferences.numberOfSecondForAutoHide).index)
        }

        let alwaysHidden = boundSwitch(UserDefaults.Key.alwaysHiddenSectionEnabled,
                                       read: { Preferences.alwaysHiddenSectionEnabled },
                                       write: { Preferences.alwaysHiddenSectionEnabled = $0 })
        let help = NSButton(title: "", target: self, action: #selector(btnAlwayHiddenHelpPressed(_:)))
        help.bezelStyle = .helpButton
        help.controlSize = .small
        let alwaysHiddenControls = NSStackView(views: [help, alwaysHidden])
        alwaysHiddenControls.spacing = 10

        onRefresh { [weak self] in self?.shortcutRecorder.refresh() }
        let hover = boundSwitch(UserDefaults.Key.hoverToExpand, read: { Preferences.hoverToExpand },
                                write: { Preferences.hoverToExpand = $0 })
        // One group for everything you set once; the preview above names it.
        var everydayRows = [
            SettingsForm.row("Open Hidden Bar at login".localized, control: login),
            SettingsForm.row("Hide icons again".localized, control: autoHidePopup),
            SettingsForm.row("Always-hidden section".localized,
                             caption: "A second group, left of the hidden icons, that stays hidden when you click the arrow.".localized,
                             control: alwaysHiddenControls),
            SettingsForm.row("Keyboard shortcut".localized, control: shortcutRecorder),
        ]
        everydayRows.append(contentsOf: findHiddenIconRows())
        addSection(nil, rows: everydayRows, spacingBefore: 16)
        addRevealSection(hover: hover)
        #if HIDDENBAR_NATIVE_VISIBILITY
        if context.usesNativeEngine {
            addPresentationSection()
        }
        #endif

        if context.usesNativeEngine {
            let value = NSTextField(labelWithString: "")
            value.font = .systemFont(ofSize: NSFont.systemFontSize)
            accessibilityValue = value
            let capture = boundSwitch(UserDefaults.Key.showWholeBarWhenCaptureStarts,
                                      read: { Preferences.showWholeBarWhenCaptureStarts },
                                      write: { Preferences.showWholeBarWhenCaptureStarts = $0 })
            addSection("Privacy and permissions".localized, rows: [
                SettingsForm.row("Accessibility".localized, control: value),
                SettingsForm.row("Show all icons when the microphone or camera turns on".localized,
                                 caption: "So you see which app is using it. Click the arrow to hide again.".localized,
                                 control: capture),
            ])
        }

        onRefresh { [weak self] in self?.refreshStatus() }
        refreshAll()
    }

    // Type-to-find palette: it lists apps from the Accessibility read and opens
    // their menus, so only the native engine has it. Unset, the feature is off.
    private func findHiddenIconRows() -> [NSView] {
        guard context.usesNativeEngine else { return [] }
        let recorder: ShortcutRecorderRow
        if let fixture = context.shortcutFixtureDefaults {
            // Snapshots show a set shortcut without touching the real preferences.
            recorder = ShortcutRecorderRow(key: UserDefaults.Key.findHiddenIconShortcut,
                                           registry: HotKeyRegistry(defaults: fixture, bind: { _, _ in nil }),
                                           defaults: fixture)
        } else {
            recorder = ShortcutRecorderRow(key: UserDefaults.Key.findHiddenIconShortcut)
        }
        findShortcutRecorder = recorder
        onRefresh { recorder.refresh() }
        return [SettingsForm.row("Find a hidden icon".localized,
                                 caption: "Opens a search under the arrow. Type a few letters, then press Return to open that app's menu.".localized,
                                 control: recorder)]
    }

    // The ways to show hidden icons without aiming at the arrow. Scroll and
    // shake need no permission; telling empty space from an icon needs
    // Accessibility, which the sandboxed App Store build cannot have, so the
    // click row is the direct build's alone.
    private func addRevealSection(hover: NSView) {
        let scroll = boundSwitch(UserDefaults.Key.revealOnScrollEnabled, read: { Preferences.revealOnScrollEnabled },
                                 write: { Preferences.revealOnScrollEnabled = $0 })
        let shake = boundSwitch(UserDefaults.Key.revealOnShakeEnabled, read: { Preferences.revealOnShakeEnabled },
                                write: { Preferences.revealOnShakeEnabled = $0 })
        var rows = [
            SettingsForm.row("Rest the pointer on the menu bar".localized, control: hover),
            SettingsForm.row("Scroll down on the menu bar".localized,
                             caption: "Scroll up to hide them again.".localized, control: scroll),
        ]
        if context.build == .direct {
            let click = boundSwitch(UserDefaults.Key.revealOnEmptyClickEnabled, read: { Preferences.revealOnEmptyClickEnabled },
                                    write: { Preferences.revealOnEmptyClickEnabled = $0 })
            rows.append(SettingsForm.row("Click empty space in the menu bar".localized, control: click))
        }
        rows.append(SettingsForm.row("Shake the pointer at the top of the screen".localized,
                                     caption: "Three quick side-to-side moves.".localized, control: shake))
        addSection("Also show hidden icons when you".localized, rows: rows)
        addFootnote("Clicking anywhere off the menu bar hides them again.".localized)
    }

    #if HIDDENBAR_NATIVE_VISIBILITY
    // Presentation mode: the automatic trigger, the sensitive apps and the
    // shortcut. The camera rule is said where people set it up.
    private func addPresentationSection() {
        let mirror = boundSwitch(UserDefaults.Key.presentationAutoMirrorEnabled,
                                 read: { Preferences.presentationAutoMirrorEnabled },
                                 write: { Preferences.presentationAutoMirrorEnabled = $0 })
        let sensitive = PresentationSensitiveAppsControl(apps: {
            PresentationSensitiveAppsControl.chips(for: Preferences.presentationSensitiveApps)
        })
        sensitive.editButton.target = self
        sensitive.editButton.action = #selector(editSensitiveApps(_:))
        onRefresh { [weak sensitive] in sensitive?.refresh() }
        let recorder = ShortcutRecorderRow(key: UserDefaults.Key.presentationShortcut)
        onRefresh { [weak recorder] in recorder?.refresh() }
        addSection("Presentation mode".localized, rows: [
            SettingsForm.row("Turn on automatically".localized, caption: "When a display is mirrored.".localized, control: mirror),
            SettingsForm.row("Sensitive apps".localized,
                             caption: "Stay hidden while presenting, even when you click the arrow, except while hiding is paused for the camera or microphone.".localized, control: sensitive),
            SettingsForm.row("Keyboard shortcut".localized, control: recorder),
        ])
        addPresentationHowItWorks()
    }

    // The same facts the first-start tip gives, in full, where people set it up.
    // Each line is one fact; none repeats the Sensitive apps caption above.
    static let howItWorksLines = [
        "Start it with the shortcut above, the arrow's right-click menu, or automatically when a display is mirrored.",
        "While it is on, every third-party app icon is hidden. macOS's own items stay. Reveal gestures and the new-app question wait.",
        "\"Find a hidden icon\" leaves sensitive apps out of its list too.",
        "If \"Show all icons when the microphone or camera turns on\" is on, a camera or microphone that turns on while you present pauses hiding once, so macOS can show which app uses it. Nothing is hidden meanwhile, sensitive apps included. Hiding resumes when you click Hide again or collapse the bar, or when the camera and microphone turn off. A camera or microphone already on when you start does not pause it. With the switch off, hiding never pauses.",
        "Stop it from the Presenting capsule, the shortcut, or the right-click menu. An automatic start also ends when mirroring stops.",
    ]

    private func addPresentationHowItWorks() {
        let title = NSTextField(labelWithString: "How it works".localized)
        title.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        title.textColor = .secondaryLabelColor
        let labels = Self.howItWorksLines.map { SettingsForm.caption($0.localized) }
        let stack = NSStackView(views: [title] + labels)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        if let last = form.arrangedSubviews.last { form.setCustomSpacing(10, after: last) }
        addFullWidth(stack)
        // Each line wraps at the width the pane has, which yields when scroll bars are always shown.
        for label in labels {
            label.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    @objc private func editSensitiveApps(_ sender: NSButton) {
        let popover = NSPopover()
        popover.contentViewController = PresentationSensitiveAppsEditor()
        popover.behavior = .transient
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    }
    #endif

    override func viewWillAppear() {
        super.viewWillAppear()
        refreshAll()
    }

    private func refreshStatus() {
        let status = context.status
        let folder = FileManager.default.displayName(atPath: Bundle.main.bundleURL.deletingLastPathComponent().path)
        statusCard.configure(status, shortcut: Preferences.globalKey?.description, runningFolder: folder)

        let alwaysHidden = context.previewAlwaysHidden ?? Preferences.alwaysHiddenSectionEnabled
        preview.boundary = PreviewBoundary.forEngine(native: context.usesNativeEngine)
        preview.showsAlwaysHidden = alwaysHidden
        var caption = preview.boundary == .arrow
            ? "Hold ⌘ and drag an icon left of the arrow to hide it.".localized
            : "Hold ⌘ and drag an icon left of the | separator to hide it.".localized
        if alwaysHidden {
            caption += " " + "Option-click the arrow to see always-hidden icons.".localized
        }
        previewCaption.stringValue = caption

        if let accessibilityValue {
            let missing = status == .needsAccessibility || (context.statusOverride == nil && AccessibilityPermission.shared.isMissing)
            let dot = NSAttributedString(string: "● ", attributes: [.foregroundColor: missing ? NSColor.systemOrange : NSColor.systemGreen,
                                                                   .font: NSFont.systemFont(ofSize: 10)])
            let text = NSMutableAttributedString(attributedString: dot)
            text.append(NSAttributedString(string: (missing ? "Off" : "Allowed").localized,
                                           attributes: [.foregroundColor: missing ? NSColor.systemOrange : NSColor.systemGreen,
                                                        .font: NSFont.systemFont(ofSize: NSFont.systemFontSize)]))
            accessibilityValue.attributedStringValue = text
        }
    }

    private func statusAction(_ status: SettingsStatus) {
        switch status {
        case .working:
            break
        case .needsAccessibility:
            AccessibilityPermission.openSystemSettings()
        case .outsideApplications:
            #if HIDDENBAR_NATIVE_VISIBILITY
            AppStoreMigration.shared.offerMoveFromSettings()
            #endif
        case .appStoreOnMacOS27:
            #if !HIDDENBAR_NATIVE_VISIBILITY
            MacOS27Notice.shared.showFromSettings()
            #endif
        }
    }

    //MARK: - Actions
    private func loginChanged(_ wanted: Bool) {
        Preferences.isAutoStart = wanted
        // On failure the pref reverts (the switch already snapped back via
        // prefsChanged); tell the user why instead of swallowing the error.
        if Preferences.isAutoStart != wanted {
            let alert = NSAlert()
            alert.messageText = "Could not update the login item".localized
            alert.informativeText = "Check System Settings > General > Login Items and make sure Hidden Bar is allowed.".localized
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    @objc func autoHideChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard AutoHideChoice.all.indices.contains(index) else { return }
        let stored = AutoHideChoice.all[index].stored
        // Delay first, so an auto-hide that starts now uses the new one.
        if let seconds = stored.seconds {
            Preferences.numberOfSecondForAutoHide = seconds
        }
        Preferences.isAutoHide = stored.isAutoHide
    }
}

//MARK: - Always-hidden help
extension PreferencesViewController {

    @IBAction func btnAlwayHiddenHelpPressed(_ sender: NSButton) {
        let controller = NSViewController()
        let label = NSTextField(labelWithString: NSLocalizedString(TutorialText.key(), comment: "Step by step tutorial"))
        label.translatesAutoresizingMaskIntoConstraints = false
        let view = NSView()
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -4),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
        ])
        controller.view = view

        let popover = NSPopover()
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.animates = true
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxX)
    }
}

//MARK: - Tutorial text per hiding engine
// The always-hidden tutorial says where to drag the translucent bar. With the
// separator engine the boundary is the normal bar "|"; with the native engine
// (macOS 27, direct build) the arrow is the boundary and there is no "|".
enum TutorialText {
    static let separatorKey = "Tutorial text"
    static let arrowBoundaryKey = "Tutorial text (arrow boundary)"

    static func key(usesNativeEngine: Bool = MenuBarEngineFactory.usesNativeEngine()) -> String {
        usesNativeEngine ? arrowBoundaryKey : separatorKey
    }
}
