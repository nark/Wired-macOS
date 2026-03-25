//
//  BoardPost.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 01/03/2026.
//  Copyright © 2026 Read-Write. All rights reserved.
//

import SwiftUI
import WiredSwift

/// Lightweight summary of a single emoji reaction on a thread or post.
struct BoardReactionSummary: Identifiable, Equatable {
    let emoji: String
    let count: Int
    /// Whether the current session account has contributed to this reaction.
    let isOwn: Bool
    /// Display nicks of everyone who reacted with this emoji (populated from reaction_list).
    var nicks: [String]

    var id: String { emoji }

    init(emoji: String, count: Int, isOwn: Bool, nicks: [String] = []) {
        self.emoji = emoji
        self.count = count
        self.isOwn = isOwn
        self.nicks = nicks
    }
}

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
    var isUnread: Bool = false
    var isThreadBody: Bool = false
    var reactions: [BoardReactionSummary] = []
    var reactionsLoaded: Bool = false
    /// Emojis that arrived from other users and haven't been animated yet (cleared after ~0.8 s).
    var newReactionEmojis: Set<String> = []

    init(uuid: String,
         threadUUID: String,
         text: String,
         nick: String,
         postDate: Date,
         icon: Data? = nil,
         isOwn: Bool = false,
         isThreadBody: Bool = false) {
        self.uuid       = uuid
        self.threadUUID = threadUUID
        self.text       = text
        self.nick       = nick
        self.postDate   = postDate
        self.icon       = icon
        self.isOwn      = isOwn
        self.isThreadBody = isThreadBody
    }
}
