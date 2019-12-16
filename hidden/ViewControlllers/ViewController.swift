//
//  ViewController.swift
//  vanillaClone
//
//  Created by Thanh Nguyen on 1/24/19.
//  Copyright © 2019 Thanh Nguyen. All rights reserved.
//

import Cocoa

class ViewController: NSViewController {

    //MARK: - Outlets
    @IBOutlet weak var checkBoxKeepLastState: NSButton!
    @IBOutlet weak var textFieldTitle: NSTextField!
    @IBOutlet weak var imageViewTop: NSImageView!
    
    @IBOutlet weak var checkBoxAutoHide: NSButton!
    @IBOutlet weak var checkBoxKeepInDock: NSButton!
    @IBOutlet weak var checkBoxLogin: NSButton!
    @IBOutlet weak var checkBoxShowPreferences: NSButton!
    
    
    //MARK: - VC Life cycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    private func setupUI(){
        imageViewTop.image = NSImage(named:NSImage.Name("banner"))
        checkBoxLogin.state = Util.getStateAutoStart()
        checkBoxAutoHide.state = Util.getStateAutoHide()
        checkBoxKeepInDock.state = Util.getStateKeepInDock()
        checkBoxShowPreferences.state = Util.getStateShowPreferences()
        checkBoxKeepLastState.state = Util.getStateKeepLastState()
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
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
}

