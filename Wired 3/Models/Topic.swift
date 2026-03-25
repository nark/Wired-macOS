//
//  Topic.swift
//  Wired-macOS
//
//  Created by Rafaël Warnault on 25/12/2025.
//  Copyright © 2025 Read-Write. All rights reserved.
//

import SwiftUI

@Observable
@MainActor
final class Topic: Identifiable {
    let id: UUID
    var topic: String = ""
    var nick: String = ""
    var time: Date
    
    init(topic: String, nick: String, time: Date) {
        self.id = UUID()
        self.topic = topic
        self.nick = nick
        self.time = time
    }
}

