//
//  StoredMessageSelection.swift
//  Wired-macOS
//

import Foundation
import SwiftData

@Model
final class StoredMessageSelection {
    @Attribute(.unique) var connectionKey: String
    var selectedConversationID: UUID?

    init(connectionKey: String, selectedConversationID: UUID?) {
        self.connectionKey = connectionKey
        self.selectedConversationID = selectedConversationID
    }
}
