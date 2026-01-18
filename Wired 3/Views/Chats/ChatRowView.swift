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
    
    @State var chat: Chat
    @State var showEditPublicChatSheet = false
    @State var showDeletePublicChatConfirm = false
    
    var body: some View {
        HStack {
            Image(systemName: "message.fill")
                .foregroundStyle(chat.joined ? Color.green : Color.black)
            Text(chat.name)
            
            Spacer()
        }
        .badge(chat.unreadMessagesCount)
        .contextMenu {
            if chat.joined {
                Button("Leave") {
                    Task {
                        do {
                            try await runtime.leaveChat(chat.id)
                            
                            chat.users.removeAll()
                            chat.joined = false
                            
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
            
            Divider()
            
            // TODO: add `wired.account.chat.edit_public_chats` message ?
//            Button("Edit") {
//                showEditPublicChatSheet.toggle()
//            }
//            .disabled(chat.id == 1 || !runtime.hasPrivilege("wired.account.chat.create_public_chats"))
//            
//            Divider()
            
            Button("Delete") {
                showDeletePublicChatConfirm.toggle()
                
            }
            .disabled(chat.id == 1 || !runtime.hasPrivilege("wired.account.chat.delete_public_chats"))
        }
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
