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
    @State private var searchText: String = ""
    @State private var isShowingSearchProgress = false
    @State var showEditPublicChatSheet = false
    @State var showDeletePublicChatConfirm = false
    @State private var chatIDToDelete: UInt32?
    #if os(macOS)
    @AppStorage("chatListWidth") private var chatListWidth: Double = 200
    #endif

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool {
        !normalizedSearchText.isEmpty
    }

    private var filteredPublicChats: [Chat] {
        runtime.chats.filter { $0.matchesSearch(normalizedSearchText) }
    }

    private var filteredPrivateChats: [Chat] {
        runtime.private_chats.filter { $0.matchesSearch(normalizedSearchText) }
    }

    private var hasSearchResults: Bool {
        !(filteredPublicChats.isEmpty && filteredPrivateChats.isEmpty)
    }

    private var selectedChat: Chat? {
        guard let chatID = runtime.selectedChatID else { return nil }
        guard let chat = runtime.chat(withID: chatID) else { return nil }
        guard chat.matchesSearch(normalizedSearchText) else { return nil }
        return chat
    }

    var body: some View {
        @Bindable var runtime = runtime

#if os(macOS)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    List(selection: $runtime.selectedChatID) {
                        if !filteredPublicChats.isEmpty {
                            Section {
                                ForEach(filteredPublicChats) { chat in
                                    ChatRowView(chat: chat, searchText: normalizedSearchText)
                                        .environment(runtime)
                                }
                            } header: {
                                Text("Public Chats")
                            }
                        }

                        if !filteredPrivateChats.isEmpty {
                            Section {
                                ForEach(filteredPrivateChats) { chat in
                                    ChatRowView(chat: chat, searchText: normalizedSearchText)
                                        .environment(runtime)
                                }
                            } header: {
                                Text("Private Chats")
                            }
                        }

                        if isSearching && !hasSearchResults {
                            ContentUnavailableView(
                                "No Results",
                                systemImage: "magnifyingglass",
                                description: Text("No chat or message matches \"\(normalizedSearchText)\".")
                            )
                            .listRowInsets(EdgeInsets(top: 24, leading: 12, bottom: 24, trailing: 12))
                            .listRowSeparator(.hidden)
                        }
                    }
                    .contextMenu(forSelectionType: UInt32.self, menu: { selectedIDs in
                        if let first = selectedIDs.first {
                            if let chat = runtime.chat(withID: UInt32(Int(first))) {
                                if chat.joined {
                                    Button("Leave") {
                                        Task {
                                            do {
                                                try await runtime.leaveChat(chat.id)
                                            } catch {
                                                runtime.lastError = error
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
                                                runtime.lastError = error
                                            }
                                        }
                                    }
                                    .disabled(chat.joined || chat.id == 1)
                                }

                                if !chat.isPrivate {
                                    Divider()

                                    // TODO: add `wired.account.chat.edit_public_chats` message ?

                                    Button("Delete") {
                                        chatIDToDelete = UInt32(Int(first))
                                        showDeletePublicChatConfirm.toggle()
                                    }
                                    .disabled(chat.id == 1 || !runtime.hasPrivilege("wired.account.chat.delete_public_chats"))
                                }
                            }
                        }

                    }, primaryAction: { selectedIDs in
                        if let first = selectedIDs.first {
                            if let chat = runtime.chat(withID: UInt32(Int(first))) {
                                if !chat.joined {
                                    Task {
                                        do {
                                            try await runtime.joinChat(chat.id)

                                        } catch {
                                            runtime.lastError = error
                                        }
                                    }
                                }
                            }
                        }
                    })
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
                    .sheet(isPresented: $showEditPublicChatSheet) {
                        if  let selectedChatID = runtime.selectedChatID,
                            let chat = runtime.chat(withID: selectedChatID) {
                            PublicChatFormView(chat: chat)
                                .environment(runtime)
                        }
                    }
                    .alert("Delete Public Chat", isPresented: $showDeletePublicChatConfirm) {
                        Button("OK", role: .destructive) {
                            Task {
                                if  let chatID = chatIDToDelete,
                                    let chat = runtime.chat(withID: chatID) {
                                    try await runtime.deletePublicChat(chat.id)
                                    runtime.selectedChatID = 1
                                }
                            }
                        }

                        Button("Cancel", role: .cancel) { }
                    } message: {
                        Text("Are you sure you want to delete this public chat? This action cannot be undone.")
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

                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 14, height: 14)
                            .opacity(isShowingSearchProgress ? 1 : 0)
                            .animation(.easeInOut(duration: 0.15), value: isShowingSearchProgress)
                            .help("Updating chat search results")
                    }
                    .padding(9)
                }
                .frame(width: chatListWidth)

                DraggableSidebarDivider(width: $chatListWidth, minWidth: 120, maxWidth: 400)

                Group {
                    if let chatID = runtime.selectedChatID,
                       let chat = selectedChat {
                        if chat.joined == true {
                            ChatView(chat: chat, searchText: normalizedSearchText)
                                .environment(runtime)
                        } else {
                            VStack {
                                ContentUnavailableView(
                                    "Join Chat",
                                    systemImage: "ellipsis.message",
                                    description: Text("You are not joined to this chat.")
                                )

                                Button {
                                    Task {
                                        do {
                                            try await runtime.joinChat(chatID)
                                        } catch {
                                            runtime.lastError = error
                                        }
                                    }
                                } label: {
                                    Text("Join Chat")
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    } else if isSearching && !hasSearchResults {
                        ContentUnavailableView(
                            "No Results",
                            systemImage: "magnifyingglass",
                            description: Text("Try another search.")
                        )
                    } else if isSearching {
                        ContentUnavailableView(
                            "Select a Chat",
                            systemImage: "line.3.horizontal.decrease.circle",
                            description: Text("Choose a chat from the filtered results.")
                        )
                    } else {
                        ContentUnavailableView(
                            "No Chat",
                            systemImage: "ellipsis.message",
                            description: Text("Select a chat from the list.")
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .searchable(text: $searchText)
        .wiredSearchFieldFocus()
        .onChange(of: normalizedSearchText) { _, query in
            guard !query.isEmpty else {
                isShowingSearchProgress = false
                return
            }

            isShowingSearchProgress = true

            DispatchQueue.main.async {
                if normalizedSearchText == query {
                    isShowingSearchProgress = false
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
        ) { _ in
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
                if !filteredPublicChats.isEmpty {
                    Section {
                        ForEach(filteredPublicChats) { chat in
                            NavigationLink {
                                ChatView(chat: chat, searchText: normalizedSearchText)
                                    .environment(runtime)
                                    .navigationTitle(chat.name)
                            } label: {
                                ChatRowView(chat: chat, searchText: normalizedSearchText)
                                    .environment(runtime)
                            }
                        }
                    } header: {
                        Text("Public Chats")
                    }
                }

                if !filteredPrivateChats.isEmpty {
                    Section {
                        ForEach(filteredPrivateChats) { chat in
                            NavigationLink {
                                ChatView(chat: chat, searchText: normalizedSearchText)
                                    .environment(runtime)
                                    .navigationTitle(chat.name)
                            } label: {
                                ChatRowView(chat: chat, searchText: normalizedSearchText)
                                    .environment(runtime)
                            }
                        }
                    } header: {
                        Text("Private Chats")
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if isSearching && !hasSearchResults {
                    ContentUnavailableView(
                        "No Results",
                        systemImage: "magnifyingglass",
                        description: Text("No chat or message matches \"\(normalizedSearchText)\".")
                    )
                }
            }
            .searchable(text: $searchText)
            .wiredSearchFieldFocus()
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
