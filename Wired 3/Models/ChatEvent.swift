//
//  ChatEvent.swift
//  Wired-macOS
//
//  Created by Rafaël Warnault on 25/12/2025.
//  Copyright © 2025 Read-Write. All rights reserved.
//

import SwiftUI

public enum ChatEventType {
case say, me, join, leave
}

@Observable
@MainActor
final class ChatEvent: Identifiable {
    
    let id: UUID
    var chat: Chat
    var user: User
    var text: String
    var type: ChatEventType
    var date = Date()
    
    init(chat: Chat, user: User, type: ChatEventType, text: String) {
        self.id = UUID()
        self.chat = chat
        self.user = user
        self.text = text
        self.type = type
    
    }
}
