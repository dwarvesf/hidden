//
//  AboutViewController.swift
//  Hidden Bar
//
//  Created by phucld on 12/19/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import Cocoa

class AboutViewController: NSViewController {

    @IBOutlet weak var lblVersion: NSTextField!
    
    static func initWithStoryboard() -> AboutViewController {
        let vc = NSStoryboard(name:"Main", bundle: nil).instantiateController(withIdentifier: "aboutVC") as! AboutViewController
        return vc
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    private func setupUI() {
        guard let version = Bundle.main.releaseVersionNumber,
                let buildNumber = Bundle.main.buildVersionNumber else { return }
        lblVersion.stringValue += " \(version) (\(buildNumber))"
    }
    
}
