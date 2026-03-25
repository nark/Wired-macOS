//
//  ChatUsersList.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 27/12/2025.
//  Copyright © 2025 Read-Write. All rights reserved.
//

import SwiftUI

private enum UserModerationActionKind: String {
    case disconnect
    case kick
    case ban

    var title: String {
        switch self {
        case .disconnect: return "Disconnect User"
        case .kick: return "Kick User"
        case .ban: return "Ban User"
        }
    }

    var buttonTitle: String {
        switch self {
        case .disconnect: return "Disconnect"
        case .kick: return "Kick"
        case .ban: return "Ban"
        }
    }
}

private struct UserModerationSheet: Identifiable {
    let kind: UserModerationActionKind
    let user: User
    let chatID: UInt32

    var id: String {
        "\(kind.rawValue)-\(chatID)-\(user.id)"
    }
}

struct ChatUsersList: View {
    @Environment(ConnectionRuntime.self) private var runtime
    @State private var selectedUserID: UInt32?
    @State private var moderationSheet: UserModerationSheet?
    @State private var moderationError: Error?
    
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

    private func canModerate(_ user: User?) -> Bool {
        guard let user else { return false }
        return user.id != runtime.userID
    }

    private func canKick(_ user: User?) -> Bool {
        guard let user, canModerate(user) else { return false }
        return chat.isPrivate || runtime.hasPrivilege("wired.account.chat.kick_users")
    }

    private func canDisconnect(_ user: User?) -> Bool {
        guard let user, canModerate(user) else { return false }
        return runtime.hasPrivilege("wired.account.user.disconnect_users")
    }

    private func canBan(_ user: User?) -> Bool {
        guard let user, canModerate(user) else { return false }
        return runtime.hasPrivilege("wired.account.user.ban_users")
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

                if user(for: selection) != nil {
                    Divider()

                    Button("Disconnect") {
                        guard let selectedUser = user(for: selection) else { return }
                        moderationSheet = UserModerationSheet(kind: .disconnect, user: selectedUser, chatID: chat.id)
                    }
                    .disabled(!canDisconnect(user(for: selection)))

                    Button("Kick") {
                        guard let selectedUser = user(for: selection) else { return }
                        moderationSheet = UserModerationSheet(kind: .kick, user: selectedUser, chatID: chat.id)
                    }
                    .disabled(!canKick(user(for: selection)))

                    Button("Ban") {
                        guard let selectedUser = user(for: selection) else { return }
                        moderationSheet = UserModerationSheet(kind: .ban, user: selectedUser, chatID: chat.id)
                    }
                    .disabled(!canBan(user(for: selection)))
                }
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
        .sheet(item: $moderationSheet) { sheet in
            UserModerationSheetView(
                runtime: runtime,
                sheet: sheet
            ) {
                moderationSheet = nil
            } onError: { error in
                moderationError = error
            }
        }
        .errorAlert(
            error: $moderationError,
            source: "Chat Moderation",
            serverName: nil,
            connectionID: runtime.id
        )
        #if os(macOS)
        .frame(width: 200)
        #endif
    }
}

private struct UserModerationSheetView: View {
    let runtime: ConnectionRuntime
    let sheet: UserModerationSheet
    let onDismiss: () -> Void
    let onError: (Error) -> Void

    @State private var reason: String = ""
    @State private var hasExpirationDate = false
    @State private var expirationDate = Date().addingTimeInterval(3600)
    @State private var isSubmitting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(sheet.kind.title)
                .font(.title3.weight(.semibold))

            Text("Target: \(sheet.user.nick)")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Message")
                    .font(.headline)

                TextField("Optional message", text: $reason, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)
            }

            if sheet.kind == .ban {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Expire")
                        .font(.headline)

                    Picker("Expire", selection: $hasExpirationDate) {
                        Text("Jamais").tag(false)
                        Text("Date").tag(true)
                    }
                    .pickerStyle(.segmented)

                    if hasExpirationDate {
                        DatePicker(
                            "Date d'expiration",
                            selection: $expirationDate,
                            in: Date()...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .datePickerStyle(.graphical)
                    }
                }
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    onDismiss()
                }
                .disabled(isSubmitting)

                Button(sheet.kind.buttonTitle) {
                    submit()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSubmitting)
            }
        }
        .padding(20)
        .frame(minWidth: 360, idealWidth: 420)
    }

    private func submit() {
        guard !isSubmitting else { return }

        isSubmitting = true

        Task {
            do {
                switch sheet.kind {
                case .disconnect:
                    try await runtime.disconnectUser(userID: sheet.user.id, reason: reason)
                case .kick:
                    try await runtime.kickUser(chatID: sheet.chatID, userID: sheet.user.id, reason: reason)
                case .ban:
                    try await runtime.banUser(
                        userID: sheet.user.id,
                        reason: reason,
                        expirationDate: hasExpirationDate ? expirationDate : nil
                    )
                }

                await MainActor.run {
                    isSubmitting = false
                    onDismiss()
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    onError(error)
                }
            }
        }
    }
}
