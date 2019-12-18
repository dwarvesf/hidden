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
    
    @IBOutlet weak var checkBoxAutoHide: NSButton!
    @IBOutlet weak var checkBoxKeepInDock: NSButton!
    @IBOutlet weak var checkBoxLogin: NSButton!
    @IBOutlet weak var checkBoxShowPreferences: NSButton!
    
    @IBOutlet weak var timePopup: NSPopUpButton!
    
    @IBOutlet weak var btnClear: NSButton!
    @IBOutlet weak var btnShortcut: NSButton!
    
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
        setupUI()
        loadHotkey()
    }
    
    //MARK: - Actions
    @IBAction func loginCheckChanged(_ sender: NSButton) {
        switch sender.state {
        case .on:
            self.autoStart(true)
            
        case .off:
            self.autoStart(false)
        default:
            break
        }
    }
    
    @objc func autoStart(_ isCheck:Bool){
        Util.setIsAutoStart(isCheck)
        Util.setUpAutoStart(isAutoStart: isCheck)
    }
    
    @IBAction func autoHideCheckChanged(_ sender: NSButton) {
        switch sender.state {
        case .on:
            Util.setIsAutoHide(true)
        case .off:
            Util.setIsAutoHide(false)
        default:
            print("")
        }
    }
    
    @IBAction func keepInDockCheckChanged(_ sender: NSButton) {
        switch sender.state {
        case .on:
            Util.setIsKeepInDock(true)
            let _ = Util.toggleDockIcon(true)
        case .off:
            Util.setIsKeepInDock(false)
            let _ = Util.toggleDockIcon(false)
        default:
            print("")
        }
    }
    
    
    @IBAction func showPreferencesChanged(_ sender: NSButton) {
        switch sender.state {
        case .on:
            Util.setShowPreferences(true)
        case .off:
            Util.setShowPreferences(false)
        default:
            break
        }
    }
    
    @IBAction func onLastKeepAppStateChange(_ sender: NSButton) {
        switch sender.state {
        case .on:
            Util.setKeepLastState(true)
        case .off:
            Util.setKeepLastState(false)
        default:
            break
        }
    }
    
    @IBAction func timePopupDidSelected(_ sender: NSPopUpButton) {
        let selectedIndex = sender.indexOfSelectedItem
        if let selectedInSecond = SelectedSecond(rawValue: selectedIndex)?.toSeconds() {
            Util.numberOfSecondForAutoHide = selectedInSecond
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
        btnShortcut.title = "Set Shortcut"
        listening = false
        btnClear.isEnabled = false
        
        // Remove globalkey from userdefault
        Preferences.GlobalKey = nil
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
        
        Preferences.GlobalKey = newGlobalKeybind
        
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
        
        updateKeybindButton(newGlobalKeybind)
        
    }
    
    private func setupUI(){
        imageViewTop.image = NSImage(named:NSImage.Name("banner"))
        checkBoxLogin.state = Util.getStateAutoStart()
        checkBoxAutoHide.state = Util.getStateAutoHide()
        checkBoxKeepInDock.state = Util.getStateKeepInDock()
        checkBoxShowPreferences.state = Util.getStateShowPreferences()
        checkBoxKeepLastState.state = Util.getStateKeepLastState()
        timePopup.selectItem(at: SelectedSecond.secondToPossition(seconds: Util.numberOfSecondForAutoHide))
    }
    
    private func loadHotkey() {
        if let globalKey = Preferences.GlobalKey {
            updateKeybindButton(globalKey)
            updateClearButton(globalKey)
        }
    }
    
    // Set the shortcut button to show the keys to press
    private func updateKeybindButton(_ globalKeybindPreference : GlobalKeybindPreferences) {
        btnShortcut.title = globalKeybindPreference.description
    }
    
    // If a keybind is set, allow users to clear it by enabling the clear button.
    private func updateClearButton(_ globalKeybindPreference : GlobalKeybindPreferences?) {
        btnClear.isEnabled = globalKeybindPreference != nil
    }
}
