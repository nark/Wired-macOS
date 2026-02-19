//
//  Chat.swift
//  Wired-macOS
//
//  Created by Rafaël Warnault on 25/12/2025.
//  Copyright © 2025 Read-Write. All rights reserved.
//

import SwiftUI

@Observable
@MainActor
final class Chat: Identifiable {
    let id: UInt32
    var name: String
    var isPrivate: Bool
    var topic: Topic?
    var joined = false
    
    var users : [User] = []
    var messages : [ChatEvent] = []
    
    var unreadMessagesCount : Int = 0
    
    init(id: UInt32, name: String, isPrivate: Bool = false) {
        self.id = id
        self.name = name
        self.isPrivate = isPrivate
    }
}
