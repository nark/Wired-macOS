//
//  ChatRowView.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 27/12/2025.
//  Copyright © 2025 Read-Write. All rights reserved.
//

import SwiftUI
#if os(macOS)
import UniformTypeIdentifiers
#endif

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
        .onDrop(of: [UTType.plainText.identifier], isTargeted: $isDropTargeted) { providers in
            guard chat.isPrivate else { return false }

            let accepted = providers.contains { provider in
                provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
            }

            guard accepted else { return false }

            for provider in providers {
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                    var stringValue: String?

                    if let data = item as? Data {
                        stringValue = String(data: data, encoding: .utf8)
                    } else if let str = item as? String {
                        stringValue = str
                    } else if let ns = item as? NSString {
                        stringValue = ns as String
                    }

                    guard let raw = stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                          let userID = UInt32(raw) else { return }

                    Task { @MainActor in
                        guard userID != runtime.userID else { return }
                        do {
                            try await runtime.inviteUserToPrivateChat(userID: userID, chatID: chat.id)
                        } catch {
                            runtime.lastError = error
                        }
                    }
                }
            }

            return true
        }
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
