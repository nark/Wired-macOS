//
//  BoardPost.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 01/03/2026.
//  Copyright © 2026 Read-Write. All rights reserved.
//

import SwiftUI
import WiredSwift

@Observable
@MainActor
final class BoardPost: Identifiable {
    let id: UUID = UUID()

    var uuid: String
    var threadUUID: String
    var text: String
    var nick: String
    var postDate: Date
    var editDate: Date?
    var icon: Data?
    var isOwn: Bool

    init(uuid: String,
         threadUUID: String,
         text: String,
         nick: String,
         postDate: Date,
         icon: Data? = nil,
         isOwn: Bool = false) {
        self.uuid       = uuid
        self.threadUUID = threadUUID
        self.text       = text
        self.nick       = nick
        self.postDate   = postDate
        self.icon       = icon
        self.isOwn      = isOwn
    }
}
