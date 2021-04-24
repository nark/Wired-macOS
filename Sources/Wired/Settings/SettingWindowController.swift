//
//  SettingWindowController.swift
//  Wired
//
//  Created by Rafael Warnault on 01/04/2021.
//  Copyright © 2021 Read-Write. All rights reserved.
//

import Cocoa

class SettingWindowController: NSWindowController {

    override func windowDidLoad() {
        super.windowDidLoad()
    
        // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
    }

    
    @IBAction func tabAction(_ sender: Any) {
        NotificationCenter.default.post(name: NSNotification.Name(rawValue: "SelectedToolbarItemChanged"), object: self.window)
    }
}
