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
