//
//  ChatSplitViewController.swift
//  Wired
//
//  Created by Rafael Warnault on 15/04/2021.
//  Copyright © 2021 Read-Write. All rights reserved.
//

import Cocoa
import WiredSwift

public class ChatSplitViewController: NSSplitViewController {
    public var chatID:UInt32 = 0
    public var chatController:ChatController?

    public override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
    }
    
}
