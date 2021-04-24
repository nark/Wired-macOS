//
//  PrivateChatController.swift
//  Wired
//
//  Created by Rafael Warnault on 17/04/2021.
//  Copyright © 2021 Read-Write. All rights reserved.
//

import Foundation
import WiredSwift

public class PrivateChatController : ChatController, ConnectionDelegate {
    public var creatorUser:UserInfo?
    public var inviteUser:UserInfo?
    
    public init(_ connection: ServerConnection, creator: UserInfo?, invite: UserInfo?) {
        super.init(connection, chat: nil)
        
        self.inviteUser     = invite
        self.creatorUser    = creator
        
        self.connection.addDelegate(self)
        
    }
    
    
    public init(_ connection: ServerConnection, message:P7Message, creator: UserInfo?) {
        super.init(connection, chat: nil)
        
        guard let chatID = message.uint32(forField: "wired.chat.id") else {
            return
        }
        
        self.creatorUser = creator
                
        self.chat = PrivateChat(message: message)
        self.usersViewController.chatID = chatID
        self.chatViewController.chatID = chatID
        
        NotificationCenter.default.post(name: .userPrivateChatCreated, object: self)
    }
    
    
    deinit {
        if let c = self.connection {
            c.removeDelegate(self)
        }
    }
    
    
    public func createChat() {
        let message = P7Message(withName: "wired.chat.create_chat", spec: spec)
        _ = self.connection.send(message: message)
    }
    
    
    public func invite() {
        if let user = self.inviteUser {
            let message = P7Message(withName: "wired.chat.invite_user", spec: spec)
            message.addParameter(field: "wired.chat.id", value: self.chat?.chatID)
            message.addParameter(field: "wired.user.id", value: user.userID)
            _ = self.connection.send(message: message)
        }
    }
    
    
    public func connectionDidReceiveMessage(connection: Connection, message: P7Message) {
        if message.name == "wired.chat.chat_created" {
            if let chatID = message.uint32(forField: "wired.chat.id") {
                self.chat = PrivateChat(message: message)
                self.usersViewController.chatID = chatID
                self.chatViewController.chatID = chatID
                
                NotificationCenter.default.post(name: .userPrivateChatCreated, object: self)
            }
        }
        else if message.name == "wired.chat.user_list.done" {
            guard let chatID = message.uint32(forField: "wired.chat.id") else {
                return
            }
            
            if self.chat?.chatID == chatID {
                self.invite()
            }
        }
        else if message.name == "wired.chat.invitation" {
            print("wired.chat.invitation")
        }
    }
    
    public func connectionDidReceiveError(connection: Connection, message: P7Message) {
        
    }
}
