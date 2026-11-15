//
//  ViewController.swift
//  vanillaClone
//
//  Created by Thanh Nguyen on 1/24/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import Cocoa
import Carbon
import HotKey

/// The General pane: status, the menu bar preview, and the everyday settings.
class PreferencesViewController: SettingsPaneController {

    static let hoverToExpandCheckBoxIdentifier = NSUserInterfaceItemIdentifier(UserDefaults.Key.hoverToExpand)
    static let autoHidePopupIdentifier = NSUserInterfaceItemIdentifier(UserDefaults.Key.isAutoHide)
    static let shortcutButtonIdentifier = NSUserInterfaceItemIdentifier(UserDefaults.Key.globalKey)

    let statusCard = StatusCardView()
    let preview = MenuBarPreviewView()
    private let previewCaption = SettingsForm.caption("")
    private let autoHidePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let btnShortcut = NSButton(title: "", target: nil, action: nil)
    private let btnClear = NSButton(title: "", target: nil, action: nil)
    private var accessibilityValue: NSTextField?

    public var listening = false {
        didSet {
            let isHighlight = listening
            DispatchQueue.main.async { [weak self] in
                self?.btnShortcut.highlight(isHighlight)
                if isHighlight { self?.btnShortcut.title = "Type a Shortcut…".localized }
            }
        }
    }

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

        btnShortcut.bezelStyle = .rounded
        btnShortcut.identifier = Self.shortcutButtonIdentifier
        btnShortcut.target = self
        btnShortcut.action = #selector(register(_:))
        btnClear.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Clear".localized)
        btnClear.isBordered = false
        btnClear.contentTintColor = .tertiaryLabelColor
        btnClear.target = self
        btnClear.action = #selector(unregister(_:))
        let shortcutControls = NSStackView(views: [btnShortcut, btnClear])
        shortcutControls.spacing = 4
        let hover = boundSwitch(UserDefaults.Key.hoverToExpand, read: { Preferences.hoverToExpand },
                                write: { Preferences.hoverToExpand = $0 })
        // One group for everything you set once; the preview above names it.
        addSection(nil, rows: [
            SettingsForm.row("Open Hidden Bar at login".localized, control: login),
            SettingsForm.row("Hide icons again".localized, control: autoHidePopup),
            SettingsForm.row("Always-hidden section".localized,
                             caption: "A second group, left of the hidden icons, that stays hidden when you click the arrow.".localized,
                             control: alwaysHiddenControls),
            SettingsForm.row("Keyboard shortcut".localized, control: shortcutControls),
            SettingsForm.row("Show icons when the pointer rests on the menu bar".localized, control: hover),
        ], spacingBefore: 16)
        loadHotkey()

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

    // When the set shortcut button is pressed start listening for the new shortcut
    @IBAction func register(_ sender: Any) {
        listening = true
        view.window?.makeFirstResponder(nil)
    }

    // If the shortcut is cleared, clear the UI and tell AppDelegate to stop listening to the previous keybind.
    @IBAction func unregister(_ sender: Any?) {
        let appDelegate = NSApplication.shared.delegate as? AppDelegate
        appDelegate?.hotKey = nil
        btnShortcut.title = "Set Shortcut".localized
        listening = false
        btnClear.isHidden = true

        // Remove globalkey from userdefault
        Preferences.globalKey = nil
    }

    public func updateGlobalShortcut(_ event: NSEvent) {
        self.listening = false

        guard let characters = event.charactersIgnoringModifiers else {return}

        let newGlobalKeybind = GlobalKeybindPreferences(
            function: event.modifierFlags.contains(.function),
            control: event.modifierFlags.contains(.control),
            command: event.modifierFlags.contains(.command),
            shift: event.modifierFlags.contains(.shift),
            option: event.modifierFlags.contains(.option),
            capsLock: event.modifierFlags.contains(.capsLock),
            carbonFlags: event.modifierFlags.carbonFlags,
            characters: characters,
            keyCode: uint32(event.keyCode))

        Preferences.globalKey = newGlobalKeybind

        updateKeybindButton(newGlobalKeybind)
        btnClear.isHidden = false

        let appDelegate = NSApplication.shared.delegate as? AppDelegate
        appDelegate?.hotKey = HotKey(keyCombo: KeyCombo(carbonKeyCode: UInt32(event.keyCode), carbonModifiers: event.modifierFlags.carbonFlags))
    }

    public func updateModiferFlags(_ event: NSEvent) {
        let newGlobalKeybind = GlobalKeybindPreferences(
            function: event.modifierFlags.contains(.function),
            control: event.modifierFlags.contains(.control),
            command: event.modifierFlags.contains(.command),
            shift: event.modifierFlags.contains(.shift),
            option: event.modifierFlags.contains(.option),
            capsLock: event.modifierFlags.contains(.capsLock),
            carbonFlags: 0,
            characters: nil,
            keyCode: uint32(event.keyCode))

        updateModifierbindButton(newGlobalKeybind)
    }

    private func loadHotkey() {
        btnShortcut.title = "Set Shortcut".localized
        btnClear.isHidden = true
        if let globalKey = Preferences.globalKey {
            updateKeybindButton(globalKey)
            btnClear.isHidden = false
        }
    }

    // Set the shortcut button to show the keys to press
    private func updateKeybindButton(_ globalKeybindPreference : GlobalKeybindPreferences) {
        btnShortcut.title = globalKeybindPreference.description

        if globalKeybindPreference.description.count <= 1 {
            unregister(nil)
        }
    }

    // Set the shortcut button to show the modifier to press
    private func updateModifierbindButton(_ globalKeybindPreference : GlobalKeybindPreferences) {
        btnShortcut.title = globalKeybindPreference.description

        if globalKeybindPreference.description.isEmpty {
            unregister(nil)
        }
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
