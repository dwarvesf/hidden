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

class PreferencesViewController: NSViewController {
    
   
    //MARK: - Outlets
    @IBOutlet weak var checkBoxKeepLastState: NSButton!
    @IBOutlet weak var textFieldTitle: NSTextField!
    @IBOutlet weak var imageViewTop: NSImageView!
    
    @IBOutlet weak var statusBarStackView: NSStackView!
    @IBOutlet weak var arrowPointToHiddenImage: NSImageView!
    @IBOutlet weak var arrowPointToAlwayHiddenImage: NSImageView!
    @IBOutlet weak var lblAlwayHidden: NSTextField!
    
    
    
    @IBOutlet weak var checkBoxAutoHide: NSButton!
    @IBOutlet weak var checkBoxKeepInDock: NSButton!
    @IBOutlet weak var checkBoxLogin: NSButton!
    @IBOutlet weak var checkBoxShowPreferences: NSButton!
    @IBOutlet weak var checkBoxShowAlwaysHiddenSection: NSButton!
    
    @IBOutlet weak var checkBoxUseFullStatusbar: NSButton!
    @IBOutlet weak var checkBoxStealthExpandIcon: NSButton!
    @IBOutlet weak var timePopup: NSPopUpButton!
    
    @IBOutlet weak var btnClear: NSButton!
    @IBOutlet weak var btnShortcut: NSButton!

    @IBOutlet weak var checkBoxNotchOverflow: NSButton!

    public var listening = false {
        didSet {
            let isHighlight = listening
            
            DispatchQueue.main.async { [weak self] in
                self?.btnShortcut.highlight(isHighlight)
            }
        }
    }
    
    //MARK: - VC Life cycle
    override func viewDidLoad() {
        super.viewDidLoad()
        updateData()
        loadHotkey()
        createTutorialView()
        // The row lives in the storyboard alongside the other Settings
        // checkboxes; hide it on hardware where the feature can't apply.
        // The containing stack view (detachesHiddenViews) reflows on its own.
        checkBoxNotchOverflow.isHidden = !NotchOverflowController.hasNotch
        addArrowStyleRow()
        addHoverToExpandRow()
        NotificationCenter.default.addObserver(self, selector: #selector(updateData), name: .prefsChanged, object: nil)
        #if HIDDENBAR_SPARKLE
        addUpdateRow()
        #endif
        #if HIDDENBAR_NATIVE_VISIBILITY
        addMacOS27Rows()
        addAccessibilityBanner()
        #endif
    }

    private var arrowStylePopup: NSPopUpButton?

    // One popup under the stealth checkbox. Each entry carries a preview of its
    // collapsed and expanded arrow; picking one redraws the status item at once.
    private func addArrowStyleRow() {
        guard let stack = checkBoxStealthExpandIcon.superview as? NSStackView,
              let index = stack.arrangedSubviews.firstIndex(of: checkBoxStealthExpandIcon) else { return }
        let label = NSTextField(labelWithString: "Arrow style".localized)
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        for style in ArrowStyle.allCases {
            let item = NSMenuItem(title: style.localizedName, action: nil, keyEquivalent: "")
            item.image = style.previewImage()
            item.representedObject = style.rawValue
            popup.menu?.addItem(item)
        }
        popup.target = self
        popup.action = #selector(arrowStyleChanged(_:))
        popup.selectItem(at: ArrowStyle.allCases.firstIndex(of: Preferences.arrowStyle) ?? 0)
        let row = NSStackView(views: [label, popup])
        row.orientation = .horizontal
        row.spacing = 8
        stack.insertArrangedSubview(row, at: index + 1)
        arrowStylePopup = popup
    }

    @objc private func arrowStyleChanged(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String else { return }
        Preferences.arrowStyle = ArrowStyle(storedValue: raw)
    }

    #if HIDDENBAR_SPARKLE
    private var checkBoxAutoUpdate: NSButton?

    // Direct build only: Sparkle owns the setting, the row just mirrors it.
    private func addUpdateRow() {
        guard let stack = checkBoxNotchOverflow.superview as? NSStackView,
              let index = stack.arrangedSubviews.firstIndex(of: checkBoxNotchOverflow) else { return }
        let checkBox = NSButton(checkboxWithTitle: "Automatically check for updates".localized,
                                target: self, action: #selector(autoUpdateChanged(_:)))
        checkBox.state = UpdateController.shared.automaticallyChecksForUpdates ? .on : .off
        stack.insertArrangedSubview(checkBox, at: index + 1)
        checkBoxAutoUpdate = checkBox
    }

    @objc private func autoUpdateChanged(_ sender: NSButton) {
        UpdateController.shared.automaticallyChecksForUpdates = sender.state == .on
    }
    #endif

    #if HIDDENBAR_NATIVE_VISIBILITY
    // macOS 27: the icons macOS hides on collapse although they sit right of the
    // arrow, and the opt-in to keep the whole bar shown while they are there.
    private var labelMacOSAlsoHides: NSTextField?
    private var checkBoxPauseHiding: NSButton?

    private func addMacOS27Rows() {
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27,
              let stack = checkBoxNotchOverflow.superview as? NSStackView,
              let index = stack.arrangedSubviews.firstIndex(of: checkBoxNotchOverflow) else { return }
        let checkBox = NSButton(checkboxWithTitle: "Show all icons while macOS would also hide one right of the arrow".localized,
                                target: self, action: #selector(pauseHidingChanged(_:)))
        let label = NSTextField(wrappingLabelWithString: "")
        label.textColor = .secondaryLabelColor
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        stack.insertArrangedSubview(checkBox, at: index + 1)
        stack.insertArrangedSubview(label, at: index + 2)
        checkBoxPauseHiding = checkBox
        labelMacOSAlsoHides = label
        NotificationCenter.default.addObserver(self, selector: #selector(updateMacOS27Rows), name: .unkeepableSystemItemsChanged, object: nil)
        updateMacOS27Rows()
    }

    @objc private func updateMacOS27Rows() {
        checkBoxPauseHiding?.state = Preferences.pauseHidingForUnkeepableItems ? .on : .off
        let names = NativeVisibilityEngine.knownUnkeepableSystemItems.map(NativeVisibilityEngine.displayName(ofSystemItem:))
        labelMacOSAlsoHides?.stringValue = String(format: "macOS 27 also hides: %@".localized, names.joined(separator: ", "))
        labelMacOSAlsoHides?.isHidden = names.isEmpty
    }

    @objc private func pauseHidingChanged(_ sender: NSButton) {
        Preferences.pauseHidingForUnkeepableItems = sender.state == .on
    }

    // macOS 27: without Accessibility the arrow cannot hide anything. Say so at
    // the top of the settings, with a way to the switch, until it is granted.
    private var accessibilityBanner: NSView?

    private func addAccessibilityBanner() {
        guard let stack = checkBoxLogin.superview as? NSStackView else { return }
        let label = NSTextField(wrappingLabelWithString: "Hidden Bar needs Accessibility access to hide icons.".localized)
        label.textColor = .systemOrange
        let button = NSButton(title: "Open Settings…".localized, target: self, action: #selector(openAccessibilitySettings(_:)))
        let row = NSStackView(views: [label, button])
        row.orientation = .horizontal
        row.spacing = 8
        stack.insertArrangedSubview(row, at: 0)
        accessibilityBanner = row
        NotificationCenter.default.addObserver(self, selector: #selector(updateAccessibilityBanner), name: .accessibilityPermissionChanged, object: nil)
        updateAccessibilityBanner()
    }

    @objc private func updateAccessibilityBanner() {
        accessibilityBanner?.isHidden = !AccessibilityPermission.shared.isMissing
    }

    @objc private func openAccessibilitySettings(_ sender: NSButton) {
        AccessibilityPermission.openSystemSettings()
    }
    #endif

    private var statusBarBelowToolbar: NSLayoutConstraint?

    // The storyboard's fixed top offset predates taller toolbars; keep the mock menu bar below it.
    func pinStatusBarBelowToolbar(of window: NSWindow) {
        guard let guide = window.contentLayoutGuide as? NSLayoutGuide else { return }
        statusBarBelowToolbar?.isActive = false
        statusBarBelowToolbar = statusBarStackView.topAnchor.constraint(greaterThanOrEqualTo: guide.topAnchor, constant: 8)
        statusBarBelowToolbar?.isActive = true
    }

    deinit {
        // Balance the viewDidLoad observer (PRs #335/#346).
        NotificationCenter.default.removeObserver(self, name: .prefsChanged, object: nil)
        #if HIDDENBAR_NATIVE_VISIBILITY
        NotificationCenter.default.removeObserver(self, name: .unkeepableSystemItemsChanged, object: nil)
        NotificationCenter.default.removeObserver(self, name: .accessibilityPermissionChanged, object: nil)
        #endif
    }

    static func initWithStoryboard() -> PreferencesViewController {
        let vc = NSStoryboard(name:"Main", bundle: nil).instantiateController(withIdentifier: "prefVC") as! PreferencesViewController
        return vc
    }
    
    //MARK: - Actions
    @IBAction func loginCheckChanged(_ sender: NSButton) {
        let wanted = sender.state == .on
        Preferences.isAutoStart = wanted
        // On failure the pref reverts (the checkbox already snapped back via
        // prefsChanged); tell the user why instead of swallowing the error.
        if Preferences.isAutoStart != wanted {
            let alert = NSAlert()
            alert.messageText = "Could not update the login item".localized
            alert.informativeText = "Check System Settings > General > Login Items and make sure Hidden Bar is allowed.".localized
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
    
    @IBAction func autoHideCheckChanged(_ sender: NSButton) {
        Preferences.isAutoHide = sender.state == .on
    }
    
    @IBAction func showPreferencesChanged(_ sender: NSButton) {
        Preferences.isShowPreference = sender.state == .on
    }
    
    
    @IBAction func showAlwaysHiddenSectionChanged(_ sender: NSButton) {
        Preferences.alwaysHiddenSectionEnabled = sender.state == .on
        createTutorialView()
    }
    @IBAction func useFullStatusBarOnExpandChanged(_ sender: NSButton) {
        Preferences.useFullStatusBarOnExpandEnabled = sender.state == .on
    }
    @IBAction func stealthExpandIconChanged(_ sender: NSButton) {
        Preferences.stealthExpandIconEnabled = sender.state == .on
    }
    
    
    @IBAction func timePopupDidSelected(_ sender: NSPopUpButton) {
        let selectedIndex = sender.indexOfSelectedItem
        if let selectedInSecond = SelectedSecond(rawValue: selectedIndex)?.toSeconds() {
            Preferences.numberOfSecondForAutoHide = selectedInSecond
        }
    }
    
    // When the set shortcut button is pressed start listening for the new shortcut
    @IBAction func register(_ sender: Any) {
        listening = true
        view.window?.makeFirstResponder(nil)
    }
    
    // If the shortcut is cleared, clear the UI and tell AppDelegate to stop listening to the previous keybind.
    @IBAction func unregister(_ sender: Any?) {
        let appDelegate = NSApplication.shared.delegate as! AppDelegate
        appDelegate.hotKey = nil
        btnShortcut.title = "Set Shortcut".localized
        listening = false
        btnClear.isEnabled = false
        
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
        btnClear.isEnabled = true
        
        let appDelegate = NSApplication.shared.delegate as! AppDelegate
        appDelegate.hotKey = HotKey(keyCombo: KeyCombo(carbonKeyCode: UInt32(event.keyCode), carbonModifiers: event.modifierFlags.carbonFlags))
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
    
    @objc private func updateData(){
        checkBoxUseFullStatusbar.state = Preferences.useFullStatusBarOnExpandEnabled ? .on : .off
        checkBoxLogin.state = Preferences.isAutoStart ? .on : .off
        checkBoxAutoHide.state = Preferences.isAutoHide ? .on : .off
        checkBoxShowPreferences.state = Preferences.isShowPreference ? .on : .off
        checkBoxShowAlwaysHiddenSection.state = Preferences.alwaysHiddenSectionEnabled ? .on : .off
        timePopup.selectItem(at: SelectedSecond.secondToPossition(seconds: Preferences.numberOfSecondForAutoHide))
        checkBoxNotchOverflow.state = Preferences.notchOverflowEnabled ? .on : .off
        checkBoxStealthExpandIcon.state = Preferences.stealthExpandIconEnabled ? .on : .off
        arrowStylePopup?.selectItem(at: ArrowStyle.allCases.firstIndex(of: Preferences.arrowStyle) ?? 0)
        #if HIDDENBAR_NATIVE_VISIBILITY
        updateMacOS27Rows()
        #endif
        #if HIDDENBAR_SPARKLE
        checkBoxAutoUpdate?.state = UpdateController.shared.automaticallyChecksForUpdates ? .on : .off
        #endif
    }
    
    private func loadHotkey() {
        if let globalKey = Preferences.globalKey {
            updateKeybindButton(globalKey)
            updateClearButton(globalKey)
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
    
    // If a keybind is set, allow users to clear it by enabling the clear button.
    private func updateClearButton(_ globalKeybindPreference : GlobalKeybindPreferences?) {
        btnClear.isEnabled = globalKeybindPreference != nil
    }
}

//MARK: - Notch Overflow Section
extension PreferencesViewController {

    @IBAction func notchOverflowCheckChanged(_ sender: NSButton) {
        Preferences.notchOverflowEnabled = sender.state == .on
    }

}

//MARK: - Show tutorial
extension PreferencesViewController {
    
    func createTutorialView() {
        if Preferences.alwaysHiddenSectionEnabled {
            alwayHideStatusBar()
        }else {
            hideStatusBar()
        }
    }
    
    func hideStatusBar() {
        lblAlwayHidden.isHidden = true
        arrowPointToAlwayHiddenImage.isHidden = true
        statusBarStackView.removeAllSubViews()
        let imageWidth: CGFloat = 16
        
        
        let images = ["ico_1","ico_2","ico_3","seprated", "ico_collapse","ico_4","ico_5","ico_6","ico_7"].map { imageName in
            NSImageView(image: NSImage(named: imageName)!)
        }
        
        
        for image in images {
            statusBarStackView.addArrangedSubview(image)
            image.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                image.widthAnchor.constraint(equalToConstant: imageWidth),
                image.heightAnchor.constraint(equalToConstant: imageWidth)
                
            ])
            image.contentTintColor = .labelColor
        }
        let dateTimeLabel = NSTextField()
        dateTimeLabel.stringValue = Date.dateString() + " " + Date.timeString()
        dateTimeLabel.translatesAutoresizingMaskIntoConstraints = false
        dateTimeLabel.isBezeled = false
        dateTimeLabel.isEditable = false
        dateTimeLabel.sizeToFit()
        dateTimeLabel.backgroundColor = .clear
        statusBarStackView.addArrangedSubview(dateTimeLabel)
        NSLayoutConstraint.activate([dateTimeLabel.heightAnchor.constraint(equalToConstant: imageWidth)
        ])
       
        NSLayoutConstraint.activate([
            arrowPointToHiddenImage.centerXAnchor.constraint(equalTo: statusBarStackView.arrangedSubviews[3].centerXAnchor)
        ])
    }
    
    func alwayHideStatusBar() {
        lblAlwayHidden.isHidden = false
        arrowPointToAlwayHiddenImage.isHidden = false
        statusBarStackView.removeAllSubViews()
        let imageWidth: CGFloat = 16
        
        
        let images = ["ico_1","ico_2","ico_3","ico_4", "seprated_1","ico_5","ico_6","seprated", "ico_collapse","ico_7"].map { imageName in
            NSImageView(image: NSImage(named: imageName)!)
        }
        
        
        for image in images {
            statusBarStackView.addArrangedSubview(image)
            image.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                image.widthAnchor.constraint(equalToConstant: imageWidth),
                image.heightAnchor.constraint(equalToConstant: imageWidth)
                
            ])
            image.contentTintColor = .labelColor
        }
        let dateTimeLabel = NSTextField()
        dateTimeLabel.stringValue = Date.dateString() + " " + Date.timeString()
        dateTimeLabel.translatesAutoresizingMaskIntoConstraints = false
        dateTimeLabel.isBezeled = false
        dateTimeLabel.isEditable = false
        dateTimeLabel.sizeToFit()
        dateTimeLabel.backgroundColor = .clear
        statusBarStackView.addArrangedSubview(dateTimeLabel)
        NSLayoutConstraint.activate([dateTimeLabel.heightAnchor.constraint(equalToConstant: imageWidth)
        ])
        
        NSLayoutConstraint.activate([
            arrowPointToAlwayHiddenImage.centerXAnchor.constraint(equalTo: statusBarStackView.arrangedSubviews[4].centerXAnchor)
        ])
        NSLayoutConstraint.activate([
            arrowPointToHiddenImage.centerXAnchor.constraint(equalTo: statusBarStackView.arrangedSubviews[7].centerXAnchor)
        ])
    }
    
    @IBAction func btnAlwayHiddenHelpPressed(_ sender: NSButton) {
        self.showHowToUseAlwayHiddenPopover(sender: sender)
    }
    
    private func showHowToUseAlwayHiddenPopover(sender: NSButton) {
        let controller = NSViewController()
        let label = NSTextField()
        let text = NSLocalizedString(TutorialText.key(), comment: "Step by step tutorial")
        
        label.stringValue = text
        label.isBezeled = false
        label.isEditable = false
        let view = NSView()
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: view.topAnchor),
            label.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        label.translatesAutoresizingMaskIntoConstraints = false
        controller.view = view
        
        let popover = NSPopover()
        popover.contentViewController = controller
        popover.contentSize = controller.view.frame.size
        
        popover.behavior = .transient
        popover.animates = true
        
        popover.show(relativeTo: self.view.bounds, of: sender , preferredEdge: NSRectEdge.maxX)
    }
}

//MARK: - Hover to expand
extension PreferencesViewController {

    static let hoverToExpandCheckBoxIdentifier = NSUserInterfaceItemIdentifier("hoverToExpandCheckBox")

    // One checkbox bound to Preferences.hoverToExpand, which used to be reachable
    // only through `defaults write`. Built in code, so the storyboard is untouched.
    func addHoverToExpandRow() {
        guard let stack = checkBoxNotchOverflow.superview as? NSStackView else { return }
        let checkBox = NSButton(checkboxWithTitle: "Expand the bar when the pointer rests on the menu bar".localized,
                                target: self, action: #selector(hoverToExpandChanged(_:)))
        checkBox.identifier = Self.hoverToExpandCheckBoxIdentifier
        checkBox.state = Preferences.hoverToExpand ? .on : .off
        stack.addArrangedSubview(checkBox)
    }

    @objc func hoverToExpandChanged(_ sender: NSButton) {
        Preferences.hoverToExpand = sender.state == .on
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
