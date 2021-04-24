//
//  Chat.swift
//  Wired
//
//  Created by Rafael Warnault on 12/04/2021.
//  Copyright © 2021 Read-Write. All rights reserved.
//

import Foundation
import WiredSwift

public class Chat {
    public var chatID:UInt32!
    public var name:String!
    public var creationNick:String!
    public var creationTime:Date!
    public var topic:String!
    public var topicNick:String!
    public var topicTime:Date!
    
    public var unreads:Int = 0
        
    public init(message: P7Message) {
        if let chatID = message.uint32(forField: "wired.chat.id") {
            self.chatID = chatID
        }
    }
}

public class PrivateChat : Chat {

}

public class PublicChat : Chat {
    public override init(message: P7Message) {
        super.init(message: message)

        if let name = message.string(forField: "wired.chat.name") {
            self.name = name
        }
    }
}
