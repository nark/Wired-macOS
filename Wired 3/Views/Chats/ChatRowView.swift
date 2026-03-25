//
//  ChatRowView.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 27/12/2025.
//  Copyright © 2025 Read-Write. All rights reserved.
//

import SwiftUI

struct ChatRowView: View {
    @Environment(ConnectionRuntime.self) private var runtime
    
    var chat: Chat
    var searchText: String = ""

#if os(macOS)
    @State private var isDropTargeted = false
#endif

    private var previewText: String? {
        chat.previewText(matching: searchText)
    }
    
    var body: some View {
        HStack {
            Image(systemName: "message.fill")
                .foregroundStyle(chat.joined ? Color.green : Color.black)

            VStack(alignment: .leading, spacing: 2) {
                Text(chat.name)

                if let previewText, !previewText.isEmpty {
                    Text(previewText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()

            UnreadCountBadge(count: chat.unreadMessagesCount)
        }
        .contentShape(Rectangle())
#if os(macOS)
        .background(isDropTargeted ? Color.accentColor.opacity(0.12) : Color.clear)
#endif
#if os(macOS)
        .dropDestination(
            for: UserDragPayload.self,
            action: { items, _ in
                guard chat.isPrivate else { return false }
                let uniqueUserIDs = Set(items.map(\.userID))
                guard !uniqueUserIDs.isEmpty else { return false }

                for userID in uniqueUserIDs {
                    Task { @MainActor in
                        guard userID != runtime.userID else { return }
                        guard chat.users.contains(where: { $0.id == userID }) == false else { return }
                        do {
                            try await runtime.inviteUserToPrivateChat(userID: userID, chatID: chat.id)
                        } catch {
                            runtime.lastError = error
                        }
                    }
                }

                return true
            },
            isTargeted: { isTargeted in
                isDropTargeted = isTargeted
            }
        )
#endif
    }
}
