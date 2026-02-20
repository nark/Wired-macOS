//
//  ChatUsersList.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 27/12/2025.
//  Copyright © 2025 Read-Write. All rights reserved.
//

import SwiftUI

struct ChatUsersList: View {
    @Environment(ConnectionRuntime.self) private var runtime
    @State private var selectedUserID: UInt32?
    
    var chat: Chat

    private func user(for selection: Set<UInt32>) -> User? {
        guard let userID = selection.first else { return nil }
        return chat.users.first(where: { $0.id == userID })
    }

    private func openPrivateMessage(for selection: Set<UInt32>) {
        guard let selectedUser = user(for: selection) else { return }
        guard runtime.hasPrivilege("wired.account.message.send_messages"),
              selectedUser.id != runtime.userID else { return }
        _ = runtime.openPrivateMessageConversation(with: selectedUser)
    }
        
    var body: some View {
        @Bindable var runtime = runtime

        Group {
#if os(macOS)
            List(chat.users, id: \.id, selection: $selectedUserID) { user in
                UserListRowView(user: user)
                    .environment(runtime)
                    .tag(user.id)
            }
            .contextMenu(forSelectionType: UInt32.self) { selection in
                Button("Get Infos") {
                    guard let selectedUser = user(for: selection) else { return }
                    runtime.getUserInfo(selectedUser.id)
                }
                .disabled(
                    !runtime.hasPrivilege("wired.account.user.get_info")
                    || user(for: selection) == nil
                )

                Divider()

                Button("Send Private Message") {
                    openPrivateMessage(for: selection)
                }
                .disabled({
                    guard let selectedUser = user(for: selection) else { return true }
                    return !runtime.hasPrivilege("wired.account.message.send_messages")
                        || selectedUser.id == runtime.userID
                }())

                Button("Invite to Private Chat") {
                    guard let selectedUser = user(for: selection) else { return }
                    Task {
                        do {
                            if chat.isPrivate {
                                try await runtime.inviteUserToPrivateChat(userID: selectedUser.id, chatID: chat.id)
                            } else {
                                try await runtime.createPrivateChat(inviting: selectedUser.id)
                            }
                        } catch {
                            runtime.lastError = error
                        }
                    }
                }
                .disabled({
                    guard let selectedUser = user(for: selection) else { return true }
                    return !runtime.hasPrivilege("wired.account.chat.create_chats")
                        || selectedUser.id == runtime.userID
                }())
            } primaryAction: { selection in
        
                openPrivateMessage(for: selection)
            }
#else
            List {
                ForEach(chat.users) { user in
                    UserListRowView(user: user)
                        .environment(runtime)
                }
            }
#endif
        }
        .popover(isPresented: $runtime.showInfos) {
            if let user = chat.users.first(where: { u in u.id == Int(runtime.showInfosUserID) }) {
                UserInfosView(user: user)
                    .environment(runtime)
            }
        }
        #if os(macOS)
        .frame(width: 200)
        #endif
    }
}
