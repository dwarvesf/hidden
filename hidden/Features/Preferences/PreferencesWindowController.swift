//
//  PreferencesWindowController.swift
//  Hidden Bar
//
//  Created by Phuc Le Dien on 2/22/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import Cocoa

class PreferencesWindowController: NSWindowController {
    
    enum MenuSegment: Int {
        case general
        case about
    }
    
    static let shared: PreferencesWindowController = {
        let wc = NSStoryboard(name:"Main", bundle: nil).instantiateController(withIdentifier: "MainWindow") as! PreferencesWindowController
        return wc
    }()
    
    private var menuSegment: MenuSegment = .general {
        didSet {
            updateVC()
        }
    }
    
    private let preferencesVC = PreferencesViewController.initWithStoryboard()
    
    private let aboutVC = AboutViewController.initWithStoryboard()
    private let pageContainer = NSViewController()
    // Shared UI dimensions in AppKit points, independent of monitor resolution.
    private let contentSize = NSSize(width: 668, height: 520)
    
    override func windowDidLoad() {
        super.windowDidLoad()
        guard let window else { return }

        // Keep one content controller for the lifetime of the window. Replacing
        // it with each page lets AppKit resize to that page's storyboard frame.
        pageContainer.view = NSView(frame: NSRect(origin: .zero, size: contentSize))
        for page in [preferencesVC as NSViewController, aboutVC as NSViewController] {
            pageContainer.addChild(page)
            page.view.translatesAutoresizingMaskIntoConstraints = false
            pageContainer.view.addSubview(page.view)
            NSLayoutConstraint.activate([
                page.view.leadingAnchor.constraint(equalTo: pageContainer.view.leadingAnchor),
                page.view.trailingAnchor.constraint(equalTo: pageContainer.view.trailingAnchor),
                page.view.topAnchor.constraint(equalTo: pageContainer.view.topAnchor),
                page.view.bottomAnchor.constraint(equalTo: pageContainer.view.bottomAnchor)
            ])
        }
        window.contentViewController = pageContainer
        window.setContentSize(contentSize)
        window.contentMinSize = contentSize
        window.contentMaxSize = contentSize

        // Center relative to the whole window, rather than relying on flexible
        // spaces around a toolbar area offset by the window controls.
        // Use the storyboard identifier directly: toolbar items can materialize
        // after windowDidLoad, so inspecting their views here can miss the tabs.
        window.toolbar?.centeredItemIdentifiers = [
            NSToolbarItem.Identifier("F7DA19CF-BC58-47E1-8140-D04939EE4CA7")
        ]
        updateVC()
    }
    
    override func keyDown(with event: NSEvent) {
        super.keyDown(with: event)
        if menuSegment == .general, preferencesVC.listening {
            preferencesVC.updateGlobalShortcut(event)
        }
    }

    // Cmd+W closes the prefs window. The main menu has no File > Close item, so
    // the key equivalent falls through to the responder chain. While the
    // shortcut recorder is listening it keeps the event, so the user can still
    // bind Cmd+W as the global hotkey.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let listening = menuSegment == .general && preferencesVC.listening
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if !listening,
           mods.isSubset(of: [.command, .shift]),
           mods.contains(.command),
           event.charactersIgnoringModifiers == "w" {
            window?.performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
    
    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        if menuSegment == .general, preferencesVC.listening {
            preferencesVC.updateModiferFlags(event)
        }
    }
    
    @IBAction func switchSegment(_ sender: NSSegmentedControl) {
        guard let segment = MenuSegment(rawValue: sender.indexOfSelectedItem) else {return}
        menuSegment = segment
    }
    
    private func updateVC() {
        preferencesVC.view.isHidden = menuSegment != .general
        aboutVC.view.isHidden = menuSegment != .about
    }
    
}
