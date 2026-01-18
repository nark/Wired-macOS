//
//  TabViewController.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 20/03/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa

class TabViewController: NSTabViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
        
        NotificationCenter.default.addObserver(
            self, selector: #selector(selectedToolbarItemChanged(_:)),
            name: NSNotification.Name(rawValue: "SelectedToolbarItemChanged"),
            object: nil)
    }
    
    @objc func selectedToolbarItemChanged(_ n:Notification) {
        if let myWindow = self.view.window {
            if let window = n.object as? NSWindow, window == myWindow {
                if let identifier = window.toolbar?.selectedItemIdentifier?.rawValue {
                    self.tabView.selectTabViewItem(withIdentifier: identifier)
                }
            }
        }
        
        // sync all windows
//        for c in ConnectionsController.shared.connections {
//            if let cwc = c.connectionWindowController {
//                if let window = cwc.window {
//                    if let identifier = window.toolbar?.selectedItemIdentifier?.rawValue {
//                        if let myWindow = self.view.window, let toolbar = myWindow.toolbar {
//                            for item in toolbar.items {
//                                if item.itemIdentifier.rawValue == identifier {
//                                    toolbar.selectedItemIdentifier = item.itemIdentifier
//                                }
//                            }
//                        }
//                        //self.tabView.selectTabViewItem(withIdentifier: identifier)
//                    }
//                }
//            }
//        }
    }
}
