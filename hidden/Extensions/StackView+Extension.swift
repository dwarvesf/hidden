//
//  StackView+Extension.swift
//  Hidden Bar
//
//  Created by Trung Phan on 22/03/2021.
//  Copyright © 2021 Dwarves Foundation. All rights reserved.
//

import Cocoa

extension NSStackView {
    func removeAllSubViews() {
        for view in self.views {
            // Deactivate constraints before removal or they leak on every
            // tutorial-view rebuild (PR #335).
            NSLayoutConstraint.deactivate(view.constraints)
            view.removeFromSuperview()
        }
    }
}
