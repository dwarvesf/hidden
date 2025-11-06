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
            // Deactivate all constraints associated with this view to prevent memory leaks
            NSLayoutConstraint.deactivate(view.constraints)
            view.removeFromSuperview()
        }
    }
}
