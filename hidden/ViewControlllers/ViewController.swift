//
//  ViewController.swift
//  vanillaClone
//
//  Created by Thanh Nguyen on 1/24/19.
//  Copyright © 2019 Thanh Nguyen. All rights reserved.
//

import Cocoa

class ViewController: NSViewController {

    @IBOutlet weak var textFieldTitle: NSTextField!
    @IBOutlet weak var imageViewTop: NSImageView!
    
    @IBOutlet weak var checkBoxAutoHide: NSButton!
   
    @IBOutlet weak var checkBoxKeepInDock: NSButton!
    @IBOutlet weak var checkBoxLogin: NSButton!
    override func viewDidLoad() {
        super.viewDidLoad()
        setUpView()
    }
    
    private func setUpView(){
        imageViewTop.image = NSImage(named:NSImage.Name("banner"))
        checkBoxLogin.state = Util.getStateAutoStart()
        checkBoxAutoHide.state = Util.getStateAutoHide()
        checkBoxKeepInDock.state = Util.getStateKeepInDock()
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }


    @IBAction func loginCheckChanged(_ sender: NSButton) {
        switch sender.state {
        case .on:
            autoStart(true)
            
        case .off:
             autoStart(false)
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
    
}

