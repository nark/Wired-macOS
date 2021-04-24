//
//  ChatPlaceholderViewController.swift
//  Wired
//
//  Created by Rafael Warnault on 14/04/2021.
//  Copyright © 2021 Read-Write. All rights reserved.
//

import Cocoa

public class ChatPlaceholderViewController: ConnectionViewController {
    @IBOutlet weak var joinButton: NSButton!
    
    
    
    // MARK: -
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidUpdate(_:)), name: NSWindow.didUpdateNotification, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    
    
    // MARK: -
    @objc public func windowDidUpdate(_ notification:Notification) {
        self.joinButton.isEnabled = self.connection != nil && self.connection.isConnected()
    }
        
    
    
    
    // MARK: -
    @IBAction func joinChat(_ sender: Any) {
        if let parentTabViewController = self.parent as? NSTabViewController {
            if let parentSplitViewController = parentTabViewController.parent as? NSSplitViewController {
                if let chatsViewController = parentSplitViewController.splitViewItems[0].viewController as? ChatsViewController {
                    chatsViewController.joinChat(sender)
                }
            }
        }
    }
}
