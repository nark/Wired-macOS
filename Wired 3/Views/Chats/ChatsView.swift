//
//  ChatsView.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 21/12/2025.
//  Copyright © 2025 Read-Write. All rights reserved.
//

import SwiftUI
import WiredSwift

struct ChatsView: View {
    @Environment(ConnectionController.self) private var connectionController
    @Environment(ConnectionRuntime.self) private var runtime
    
    @State private var visibility: NavigationSplitViewVisibility = .all
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar
    
    @State var showCreatePublicChatSheet = false

    private var selectedChat: Chat? {
        guard let chatID = runtime.selectedChatID else { return nil }
        return runtime.chat(withID: chatID)
    }
        
    var body: some View {
        @Bindable var runtime = runtime
        
#if os(macOS)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    List(selection: $runtime.selectedChatID) {
                        Section {
                            ForEach(runtime.chats) { chat in
                                ChatRowView(chat: chat)
                                    .environment(runtime)
                            }
                        } header: {
                            Text("Public Chats")
                        }
                        
                        Section {
                            ForEach(runtime.private_chats) { chat in
                                ChatRowView(chat: chat)
                                    .environment(runtime)
                            }
                        } header: {
                            Text("Private Chats")
                        }
                    }
                    .onChange(of: runtime.selectedChatID) { old, new in
                        if new == nil {
                            runtime.selectedChatID = old
                        } else {
                            if let chat = runtime.chat(withID: new!) {
                                runtime.resetUnreads(chat)
                            }
                        }
                    }
                    .onAppear {
                        ensureDefaultSelectedChat()
                    }
                    .onChange(of: runtime.chats.count) { _, _ in
                        ensureDefaultSelectedChat()
                    }
                    .listStyle(.plain)
                    
                    Divider()
                    
                    HStack {
                        Menu("", systemImage: "plus") {
                            Button("New Public Chat") {
                                showCreatePublicChatSheet.toggle()
                            }
                            .disabled(!runtime.hasPrivilege("wired.account.chat.create_public_chats"))
                            
                            Button("New Private Chat") {
                                Task {
                                    do {
                                        _ = try await runtime.createPrivateChat()
                                    } catch {
                                        runtime.lastError = error
                                    }
                                }
                            }
                            .disabled(!runtime.hasPrivilege("wired.account.chat.create_chats"))
                        }
                        .menuStyle(.borderlessButton)
                        .frame(maxWidth: 30)
                        
                        Spacer()
                    }
                    .padding(9)
                }
                .frame(width: 200)
                
                Divider()
                
                if let chatID = runtime.selectedChatID,
                   let chat = selectedChat {
                    if chat.joined == true {
                        ChatView(chat: chat)
                            .environment(runtime)
                    } else {
                        VStack {
                            Button {
                                Task {
                                    try? await runtime.joinChat(chatID)
                                }
                            } label: {
                                Text("Join Chat")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }        
        }
        .sheet(isPresented: $showCreatePublicChatSheet) {
            PublicChatFormView()
                .environment(runtime)
        }
        .alert(
            "Private Chat Invitation",
            isPresented: Binding(
                get: { runtime.pendingChatInvitation != nil },
                set: { isPresented in
                    if isPresented == false {
                        runtime.pendingChatInvitation = nil
                    }
                }
            ),
            presenting: runtime.pendingChatInvitation
        ) { invitation in
            Button("Accept") {
                runtime.acceptPendingChatInvitation()
            }

            Button("Decline", role: .destructive) {
                runtime.declinePendingChatInvitation()
            }
        } message: { invitation in
            if let nick = invitation.inviterNick, !nick.isEmpty {
                Text("\(nick) invited you to a private chat.")
            } else {
                Text("You were invited to a private chat.")
            }
        }
#elseif os(iOS)
        NavigationStack {
            List(selection: $runtime.selectedChatID) {
                Section {
                    ForEach(runtime.chats) { chat in
                        NavigationLink {
                            ChatView(chat: chat)
                                .environment(runtime)
                                .navigationTitle(chat.name)
                        } label: {
                            ChatRowView(chat: chat)
                                .environment(runtime)
                        }
                    }
                } header: {
                    Text("Public Chats")
                }
                
                Section {
                    ForEach(runtime.private_chats) { chat in
                        NavigationLink {
                            ChatView(chat: chat)
                                .environment(runtime)
                                .navigationTitle(chat.name)
                        } label: {
                            ChatRowView(chat: chat)
                                .environment(runtime)
                        }
                    }
                } header: {
                    Text("Private Chats")
                }
            }
            .listStyle(.plain)
            .onAppear {
                ensureDefaultSelectedChat()
            }
            .onChange(of: runtime.chats.count) { _, _ in
                ensureDefaultSelectedChat()
            }
        }
#endif
    }

    private func ensureDefaultSelectedChat() {
        if let selected = runtime.selectedChatID,
           runtime.chat(withID: selected) != nil {
            return
        }

        if let publicMain = runtime.chats.first(where: { $0.id == 1 }) {
            runtime.selectedChatID = publicMain.id
            runtime.resetUnreads(publicMain)
            return
        }

        if let firstPublic = runtime.chats.first {
            runtime.selectedChatID = firstPublic.id
            runtime.resetUnreads(firstPublic)
        }
    }
}
