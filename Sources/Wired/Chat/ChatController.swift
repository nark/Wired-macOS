//
//  ChatController.swift
//  Wired
//
//  Created by Rafael Warnault on 12/04/2021.
//  Copyright © 2021 Read-Write. All rights reserved.
//

import Foundation
import WiredSwift

public class ChatController : ConnectionObject {
    public var chat:Chat?
    public var chatSplitViewController:ChatSplitViewController
    public var chatViewController:ChatViewController!
    public var usersViewController:UsersViewController!
    public var usersController:UsersController
    
    public var messages:[Any] = []
    public var sentMessages:[P7Message] = []
    public var receivedMessages:[P7Message] = []
    
    
    public init(_ connection: ServerConnection, chat:Chat?) {
        self.usersController    = UsersController(connection)
        self.chat               = chat
                
        let storyboard                  = NSStoryboard(name: NSStoryboard.Name("Main"), bundle: Bundle.main)
        self.chatSplitViewController    = (storyboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier("ChatSplitViewController")) as? ChatSplitViewController)!
        self.chatViewController         = (storyboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier("ChatViewController")) as? ChatViewController)!
        self.usersViewController        = (storyboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier("UsersViewController")) as? UsersViewController)!
        
        super.init(connection)
        
        self.chatViewController.representedObject   = connection
        self.chatViewController.chatController      = self
        
        if let chatID = chat?.chatID {
            self.chatViewController.chatID = chatID
        }
        
        self.usersViewController.representedObject  = connection
        self.usersViewController.chatController     = self
        
        if let chatID = chat?.chatID {
            self.usersViewController.chatID = chatID
        }
        
        self.chatViewController.loadView()
        self.usersViewController.loadView()
    }
    
    
    public func join() {
        _ = self.connection.joinChat(chatID: self.chat!.chatID)
    }
    
    
    public func leave() {
        let message = P7Message(withName: "wired.chat.leave_chat", spec: spec)
        message.addParameter(field: "wired.chat.id", value: chat!.chatID)
        
        _ = self.connection.send(message: message)
    }
    
    
    // MARK: -
    
    public func numberOfMessage() -> Int {
        return self.messages.count
    }
    

}
