//
//  StoredPrivateConversation.swift
//  Wired-macOS
//

import Foundation
import SwiftData

@Model
final class StoredPrivateConversation {
    @Attribute(.unique) var storageID: UUID
    var conversationID: UUID
    var connectionKey: String
    var title: String
    var participantNick: String?
    var participantUserID: UInt32?
    var unreadMessagesCount: Int
    var lastUpdatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \StoredPrivateMessage.conversation)
    var messages: [StoredPrivateMessage] = []

    init(
        conversationID: UUID,
        connectionKey: String,
        title: String,
        participantNick: String?,
        participantUserID: UInt32?,
        unreadMessagesCount: Int,
        lastUpdatedAt: Date
    ) {
        self.storageID = UUID()
        self.conversationID = conversationID
        self.connectionKey = connectionKey
        self.title = title
        self.participantNick = participantNick
        self.participantUserID = participantUserID
        self.unreadMessagesCount = unreadMessagesCount
        self.lastUpdatedAt = lastUpdatedAt
    }
}
