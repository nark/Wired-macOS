//
//  StoredBroadcastConversation.swift
//  Wired-macOS
//

import Foundation
import SwiftData

@Model
final class StoredBroadcastConversation {
    @Attribute(.unique) var storageID: UUID
    var conversationID: UUID
    var connectionKey: String
    var title: String
    var unreadMessagesCount: Int
    var lastUpdatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \StoredBroadcastMessage.conversation)
    var messages: [StoredBroadcastMessage] = []

    init(
        conversationID: UUID,
        connectionKey: String,
        title: String,
        unreadMessagesCount: Int,
        lastUpdatedAt: Date
    ) {
        self.storageID = UUID()
        self.conversationID = conversationID
        self.connectionKey = connectionKey
        self.title = title
        self.unreadMessagesCount = unreadMessagesCount
        self.lastUpdatedAt = lastUpdatedAt
    }
}
