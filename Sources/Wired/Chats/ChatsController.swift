//
//  ChatsController.swift
//  Wired
//
//  Created by Rafael Warnault on 12/04/2021.
//  Copyright © 2021 Read-Write. All rights reserved.
//

import Foundation
import WiredSwift

public class ChatsController: ConnectionObject {
    public var chats:[UInt32:Chat] = [:]
    
    public var publicChats:[PublicChat] = []
    public var privateChats:[PrivateChat] = []
    

    public func getChats() {
        let message = P7Message(withName: "wired.chat.get_chats", spec: spec)
        
        _ = self.connection.send(message: message)
    }
    
    
    public func addPublicChat(_ chat: PublicChat) {
        self.publicChats.append(chat)
        self.chats[chat.chatID] = chat
    }
    
    
    public func addPrivateChat(_ chat: PrivateChat) {
        self.privateChats.append(chat)
        self.chats[chat.chatID] = chat
    }
    
    public func removePrivateChat(_ chat: PrivateChat) {
        self.privateChats.removeAll(where: { (privateChat) -> Bool in
            privateChat.chatID == chat.chatID
        })
        
        self.chats[chat.chatID] = nil
    }
    
    
    public func clearChats() {
        self.publicChats    = []
        self.privateChats   = []
        self.chats          = [:]
    }
}
