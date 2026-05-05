//
//  ChatEvent.swift
//  Wired-macOS
//
//  Created by Rafaël Warnault on 25/12/2025.
//  Copyright © 2025 Read-Write. All rights reserved.
//

import SwiftUI

public enum ChatEventType {
    case say, me, join, leave, event

    var rawStorageValue: Int {
        switch self {
        case .say: return 0
        case .me: return 1
        case .join: return 2
        case .leave: return 3
        case .event: return 4
        }
    }

    init(rawStorageValue: Int) {
        switch rawStorageValue {
        case 0: self = .say
        case 1: self = .me
        case 2: self = .join
        case 3: self = .leave
        default: self = .event
        }
    }
}

/// Lightweight summary of a single emoji reaction on a chat message.
/// Mirror of `BoardReactionSummary`, kept separate so the two surfaces
/// can evolve independently.
struct ChatReactionSummary: Identifiable, Equatable {
    let emoji: String
    let count: Int
    let isOwn: Bool
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
final class ChatEvent: Identifiable {

    let id: UUID
    var chat: Chat
    var user: User
    var text: String
    var type: ChatEventType
    var date = Date()
    var attachments: [ChatAttachmentDescriptor]

    /// Server-stamped message id (Wired 3.2). Nil on pre-3.2 servers and on
    /// archived messages from before the field was introduced. Used to
    /// correlate reactions back to the message.
    var serverMessageID: String?

    /// Reaction summaries for this message. Only populated on 3.2 servers
    /// after a `wired.chat.get_reactions` round-trip or an incoming
    /// `wired.chat.reaction_added`/`reaction_removed` broadcast.
    var reactions: [ChatReactionSummary] = []
    var reactionsLoaded: Bool = false
    /// Emojis that arrived from other users and haven't been animated yet.
    var newReactionEmojis: Set<String> = []

    /// When non-nil, overrides `user.id == runtime.userID` for display alignment.
    /// Set for archived messages where the original userID may differ from the current session.
    var isFromCurrentUser: Bool?

    /// Lazily computed on first access and cached for the lifetime of the event.
    /// `text` is effectively immutable after init, so the cache is always valid.
    /// `@ObservationIgnored` keeps this out of SwiftUI's dependency tracking.
    @ObservationIgnored private var _imageURLCached = false
    @ObservationIgnored private var _cachedPrimaryImageURL: URL?

    var cachedPrimaryHTTPImageURL: URL? {
        if !_imageURLCached {
            _imageURLCached = true
            _cachedPrimaryImageURL = text.detectedHTTPImageURLs().first
        }
        return _cachedPrimaryImageURL
    }

    init(chat: Chat, user: User, type: ChatEventType, text: String, date: Date = Date()) {
        self.attachments = []
        self.id = UUID()
        self.chat = chat
        self.user = user
        self.text = text
        self.type = type
        self.date = date
    }

    init(
        chat: Chat,
        user: User,
        type: ChatEventType,
        text: String,
        date: Date = Date(),
        attachments: [ChatAttachmentDescriptor]
    ) {
        self.id = UUID()
        self.chat = chat
        self.user = user
        self.text = text
        self.type = type
        self.date = date
        self.attachments = attachments
    }
}
