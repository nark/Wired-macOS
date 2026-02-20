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
    @State var showEditPublicChatSheet = false
    @State var showDeletePublicChatConfirm = false
#if os(macOS)
    @State private var isDropTargeted = false
#endif
    
    var body: some View {
        HStack {
            Image(systemName: "message.fill")
                .foregroundStyle(chat.joined ? Color.green : Color.black)
            Text(chat.name)
            
            Spacer()
        }
        .contentShape(Rectangle())
#if os(macOS)
        .background(isDropTargeted ? Color.accentColor.opacity(0.12) : Color.clear)
#endif
        .badge(chat.unreadMessagesCount)
        .contextMenu {
            if chat.joined {
                Button("Leave") {
                    Task {
                        do {
                            try await runtime.leaveChat(chat.id)
                        } catch {
                            
                        }
                    }
                }
                .disabled(!chat.joined || chat.id == 1)
            } else {
                Button("Join") {
                    Task {
                        do {
                            try await runtime.joinChat(chat.id)
                            
                        } catch {
                            
                        }
                    }
                }
                .disabled(chat.joined || chat.id == 1)
            }
            
            if !chat.isPrivate {
                Divider()
                
                // TODO: add `wired.account.chat.edit_public_chats` message ?
//                Button("Edit") {
//                    showEditPublicChatSheet.toggle()
//                }
//                .disabled(chat.id == 1 || !runtime.hasPrivilege("wired.account.chat.create_public_chats"))
//                
//                Divider()
                
                Button("Delete") {
                    showDeletePublicChatConfirm.toggle()
                    
                }
                .disabled(chat.id == 1 || !runtime.hasPrivilege("wired.account.chat.delete_public_chats"))
            }
        }
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
        .sheet(isPresented: $showEditPublicChatSheet) {
            PublicChatFormView(chat: chat)
                .environment(runtime)
        }
        .alert("Delete Public Chat", isPresented: $showDeletePublicChatConfirm) {
            Button("OK", role: .destructive) {
                Task {
                    try await runtime.deletePublicChat(chat.id)
                    runtime.selectedChatID = 1
                }
            }
            
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete this public chat? This action cannot be undone.")
        }
    }
}
