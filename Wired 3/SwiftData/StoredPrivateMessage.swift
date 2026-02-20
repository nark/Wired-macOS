//
//  StoredPrivateMessage.swift
//  Wired-macOS
//

import Foundation
import SwiftData

@Model
final class StoredPrivateMessage {
    @Attribute(.unique) var eventID: UUID
    var senderNick: String
    var senderUserID: UInt32?
    var senderIcon: Data?
    var text: String
    var date: Date
    var isFromCurrentUser: Bool
    var conversation: StoredPrivateConversation?

    init(
        eventID: UUID,
        senderNick: String,
        senderUserID: UInt32?,
        senderIcon: Data?,
        text: String,
        date: Date,
        isFromCurrentUser: Bool,
        conversation: StoredPrivateConversation
    ) {
        self.eventID = eventID
        self.senderNick = senderNick
        self.senderUserID = senderUserID
        self.senderIcon = senderIcon
        self.text = text
        self.date = date
        self.isFromCurrentUser = isFromCurrentUser
        self.conversation = conversation
    }
}
