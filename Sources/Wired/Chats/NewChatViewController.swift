//
//  NewChatViewController.swift
//  Wired
//
//  Created by Rafael Warnault on 11/04/2021.
//  Copyright © 2021 Read-Write. All rights reserved.
//

import Cocoa
import WiredSwift

class NewChatViewController: ConnectionViewController {
    @IBOutlet weak var nameTextField: NSTextField!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
    }
    
    @IBAction func cancel(_ sender: Any) {
        NSApp.mainWindow?.windowController?.window?.endSheet(self.view.window!, returnCode: NSApplication.ModalResponse.cancel)
    }
    
    @IBAction func ok(_ sender: Any) {
        if nameTextField.stringValue.count == 0 {
            return
        }
                
        let message = P7Message(withName: "wired.chat.create_public_chat", spec: spec)
        message.addParameter(field: "wired.chat.name", value: nameTextField.stringValue)
        
        if self.connection.send(message: message) {
            NSApp.mainWindow?.windowController?.window?.endSheet(self.view.window!, returnCode: NSApplication.ModalResponse.OK)
        }
    }
}
