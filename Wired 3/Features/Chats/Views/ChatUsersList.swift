//
//  ChatUsersList.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 27/12/2025.
//  Copyright © 2025 Read-Write. All rights reserved.
//

import SwiftUI

// MARK: - Moderation helpers

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

// MARK: - View

struct ChatUsersList: View {
    @Environment(ConnectionRuntime.self) private var runtime
    @State private var selectedOnlineID: UInt32?
    @State private var selectedOfflineLogin: String?
    @State private var moderationSheet: UserModerationSheet?
    @State private var moderationError: Error?

    var chat: Chat

    private var offlineUsers: [OfflineUser] {
        // Hide the panel entirely if the user lost the privilege mid-session;
        // the server stops pushing entries but the cached list stays in memory
        // until the privileges-update handler clears it.
        guard runtime.hasPrivilege("wired.account.user.list_offline_users") else {
            return []
        }
        // Prefer matching by login (precise) but fall back to nick: user_join
        // broadcasts include the nick but not the login (the wired.user.info
        // collection deliberately omits login to avoid leaking auth credentials),
        // so login on chat.users is empty for users we never queried via
        // get_info. Nick covers the common case of a user reconnecting with a
        // stable nick; collisions or post-disconnect nick changes are rare
        // enough that a temporary duplicate row is acceptable.
        let onlineLogins = Set(chat.users.compactMap { $0.login.isEmpty ? nil : $0.login })
        let onlineNicks = Set(chat.users.map { $0.nick }.filter { !$0.isEmpty })
        return runtime.offlineUsers.filter { offline in
            !onlineLogins.contains(offline.login) && !onlineNicks.contains(offline.nick)
        }
    }

    private var selectedOnlineUser: User? {
        guard let id = selectedOnlineID else { return nil }
        return chat.users.first(where: { $0.id == id })
    }

    private func openPrivateMessage(for selection: Set<UInt32>) {
        guard let id = selection.first,
              let user = chat.users.first(where: { $0.id == id }) else { return }
        guard runtime.hasPrivilege("wired.account.message.send_messages"),
              user.id != runtime.userID else { return }
        _ = runtime.openPrivateMessageConversation(with: user)
    }

    private func openOfflinePrivateMessage(login: String) {
        guard runtime.hasPrivilege("wired.account.message.send_offline_messages") else { return }
        guard let offlineUser = runtime.offlineUsers.first(where: { $0.login == login }) else { return }
        _ = runtime.openOfflineMessageConversation(with: offlineUser)
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
            if offlineUsers.isEmpty {
                onlineList
            } else {
                VSplitView {
                    onlineList
                        .frame(minHeight: 60)
                    offlineList
                        .frame(minHeight: 40)
                }
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
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var onlineList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Online")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                Spacer()
            }
            .background(.bar)

            List(selection: $selectedOnlineID) {
                ForEach(chat.users) { user in
                    UserListRowView(user: user)
                        .environment(runtime)
                        .tag(user.id)
                }
            }
            .contextMenu(forSelectionType: UInt32.self) { selection in
                let user = selection.first.flatMap { id in chat.users.first(where: { $0.id == id }) }

                Button("Get Infos") {
                    guard let user else { return }
                    runtime.getUserInfo(user.id)
                }
                .disabled(!runtime.hasPrivilege("wired.account.user.get_info") || user == nil)

                Divider()

                Button("Send Private Message") {
                    openPrivateMessage(for: selection)
                }
                .disabled({
                    guard let user else { return true }
                    return !runtime.hasPrivilege("wired.account.message.send_messages")
                        || user.id == runtime.userID
                }())

                Button("Invite to Private Chat") {
                    guard let user else { return }
                    Task {
                        do {
                            if chat.isPrivate {
                                try await runtime.inviteUserToPrivateChat(userID: user.id, chatID: chat.id)
                            } else {
                                try await runtime.createPrivateChat(inviting: user.id)
                            }
                        } catch {
                            runtime.lastError = error
                        }
                    }
                }
                .disabled({
                    guard let user else { return true }
                    return !runtime.hasPrivilege("wired.account.chat.create_chats")
                        || user.id == runtime.userID
                }())

                if user != nil {
                    Divider()

                    Button("Disconnect") {
                        guard let user else { return }
                        moderationSheet = UserModerationSheet(kind: .disconnect, user: user, chatID: chat.id)
                    }
                    .disabled(!canDisconnect(user))

                    Button("Kick") {
                        guard let user else { return }
                        moderationSheet = UserModerationSheet(kind: .kick, user: user, chatID: chat.id)
                    }
                    .disabled(!canKick(user))

                    Button("Ban") {
                        guard let user else { return }
                        moderationSheet = UserModerationSheet(kind: .ban, user: user, chatID: chat.id)
                    }
                    .disabled(!canBan(user))
                }
            } primaryAction: { selection in
                openPrivateMessage(for: selection)
            }
        }
    }

    @ViewBuilder
    private var offlineList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Offline")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                Spacer()
            }
            .background(.bar)

            List(selection: $selectedOfflineLogin) {
                ForEach(offlineUsers) { offlineUser in
                    Text(offlineUser.nick)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .tag(offlineUser.login)
                }
            }
            .contextMenu(forSelectionType: String.self) { selection in
                Button("Send Private Message") {
                    guard let login = selection.first else { return }
                    openOfflinePrivateMessage(login: login)
                }
                .disabled(!runtime.hasPrivilege("wired.account.message.send_offline_messages")
                          || selection.first == nil)
            } primaryAction: { selection in
                guard let login = selection.first else { return }
                openOfflinePrivateMessage(login: login)
            }
        }
    }
}

// MARK: - Moderation sheet view

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
                        Text("Never").tag(false)
                        Text("Date").tag(true)
                    }
                    .pickerStyle(.segmented)

                    if hasExpirationDate {
                        DatePicker(
                            "Expiration date",
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
