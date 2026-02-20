//
//  ConnectionController.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 18/12/2025.
//  Copyright © 2025 Read-Write. All rights reserved.
//

import SwiftUI
import SwiftData
import WiredSwift
import UserNotifications

extension Notification.Name {
    static let wiredAccountAccountsChanged = Notification.Name("wiredAccountAccountsChanged")
}

enum SocketEvent {
    case connected(UUID, Connection)
    case received(UUID, Connection, P7Message)
    case disconnected(UUID, Connection?, Error?)

    var id: UUID {
        switch self {
        case .connected(let id, _): return id
        case .received(let id, _, _): return id
        case .disconnected(let id, _, _): return id
        }
    }
}

struct NewConnectionDraft: Identifiable, Equatable {
    var id = UUID()
    var hostname: String = ""
    var login: String = ""
    var password: String = ""
}

struct TemporaryConnection: Identifiable, Hashable {
    let id: UUID
    var name: String
    var hostname: String
    var login: String
}

struct IncomingURLAction {
    let connectionID: UUID
    let remotePath: String?
}

struct ConnectionConfiguration: Identifiable, @unchecked Sendable {
    let id: UUID
    let name: String
    let hostname: String
    let login: String
    let password: String?
    let cipher: P7Socket.CipherType
    let compression: P7Socket.Compression
    let checksum: P7Socket.Checksum

    var url: Url {
        Url(withString: "wired://\(login)@\(hostname)")
    }

    init(bookmark: Bookmark, password: String? = nil) {
        self.id = bookmark.id
        self.name = bookmark.name
        self.hostname = bookmark.hostname
        self.login = bookmark.login
        self.password = password
        self.cipher = bookmark.cipher
        self.compression = bookmark.compression
        self.checksum = bookmark.checksum
    }

    init(
        id: UUID = UUID(),
        name: String,
        hostname: String,
        login: String,
        password: String?,
        cipher: P7Socket.CipherType = .ECDH_CHACHA20_POLY1305,
        compression: P7Socket.Compression = .LZ4,
        checksum: P7Socket.Checksum = .HMAC_256
    ) {
        self.id = id
        self.name = name
        self.hostname = hostname
        self.login = login
        self.password = password
        self.cipher = cipher
        self.compression = compression
        self.checksum = checksum
    }
}

@Observable
final class ConnectionController {

    // MARK: - Dependencies

    let socketClient: SocketClient
    var runtimeStores: [ConnectionRuntime] = []
    var connectionEvents: [SocketEvent] = []
    var temporaryConnections: [TemporaryConnection] = []
    var presentedNewConnection: NewConnectionDraft? = nil
    var requestedSelectionID: UUID? = nil
    var activeConnectionID: UUID? = nil
    
    // MARK: - Runtime

    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var configurationsByID: [UUID: ConnectionConfiguration] = [:]
    private var modelContext: ModelContext?

    // MARK: - Init

    init(
        socketClient: SocketClient
    ) {
        self.socketClient = socketClient
        
        NotificationCenter.default.addObserver(self, selector: #selector(wiredUserNickDidChange), name: .wiredUserNickDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(wiredUserStatusDidChange), name: .wiredUserStatusDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(wiredUserIconDidChange), name: .wiredUserIconDidChange, object: nil)
    }
    
    func runtime(for id: UUID) -> ConnectionRuntime? {
        runtimeStores.first { $0.id == id }
    }

    func configuration(for id: UUID) -> ConnectionConfiguration? {
        configurationsByID[id]
    }

    func temporaryConnection(for id: UUID) -> TemporaryConnection? {
        temporaryConnections.first(where: { $0.id == id })
    }

    func presentNewConnection(prefill: NewConnectionDraft = NewConnectionDraft()) {
        presentedNewConnection = prefill
    }

    func connectTemporary(_ draft: NewConnectionDraft) -> UUID? {
        let hostname = draft.hostname.trimmingCharacters(in: .whitespacesAndNewlines)
        let login = draft.login.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hostname.isEmpty, !login.isEmpty else { return nil }

        let id = UUID()
        let displayName = hostname
        let configuration = ConnectionConfiguration(
            id: id,
            name: displayName,
            hostname: hostname,
            login: login,
            password: draft.password
        )

        let temporary = TemporaryConnection(
            id: id,
            name: displayName,
            hostname: hostname,
            login: login
        )
        temporaryConnections.append(temporary)
        connect(configuration)
        requestedSelectionID = id
        return id
    }

    func connectOrReuseTemporary(_ draft: NewConnectionDraft) -> UUID? {
        let hostname = draft.hostname.trimmingCharacters(in: .whitespacesAndNewlines)
        let login = draft.login.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hostname.isEmpty, !login.isEmpty else { return nil }

        if let existing = configurationsByID.values.first(where: {
            $0.hostname.caseInsensitiveCompare(hostname) == .orderedSame &&
            $0.login.caseInsensitiveCompare(login) == .orderedSame
        }) {
            connect(existing)
            requestedSelectionID = existing.id
            return existing.id
        }

        return connectTemporary(draft)
    }

    func markConnectionAsBookmarked(_ id: UUID) {
        temporaryConnections.removeAll { $0.id == id }
    }

    func disconnect(connectionID: UUID, runtime: ConnectionRuntime) {
        tasks[connectionID]?.cancel()
        tasks[connectionID] = nil

        Task {
            await socketClient.disconnect(id: connectionID)

            await MainActor.run {
                runtime.disconnect(error: nil)
            }
        }
    }

    func securityOptions(for connectionID: UUID?) -> (
        cipher: P7Socket.CipherType,
        compression: P7Socket.Compression,
        checksum: P7Socket.Checksum
    )? {
        guard let connectionID, let configuration = configurationsByID[connectionID] else {
            return nil
        }
        return (
            cipher: configuration.cipher,
            compression: configuration.compression,
            checksum: configuration.checksum
        )
    }

    
    // MARK: - Notifications
    
    @MainActor @objc func wiredUserNickDidChange(_ notification: Notification) {
        if let nick = notification.object as? String {
            for r in runtimeStores {
                if let message = r.setNickMessage(nick) {
                    Task {
                        try? await r.send(message)
                    }
                }
            }
        }
    }
    
    @MainActor @objc func wiredUserStatusDidChange(_ notification: Notification) {
        if let status = notification.object as? String {
            for r in runtimeStores {
                if let message = r.setStatusMessage(status) {
                    Task {
                        _ = try? await r.send(message)
                    }
                }
            }
        }
    }
    
    @MainActor @objc func wiredUserIconDidChange(_ notification: Notification) {
        if let icon = notification.object as? String {
            if let data = Data(base64Encoded: icon, options: .ignoreUnknownCharacters) {
                for r in runtimeStores {
                    if let message = r.setIconMessage(data) {
                        Task {
                            try? await r.send(message)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - IdleTimers
    
    @MainActor func startIdleTimers() {
        for r in runtimeStores {
            r.startIdleTimer()
        }
    }

    @MainActor func stopIdleTimers() {
        for r in runtimeStores {
            r.stopIdleTimer()
        }
    }

    // MARK: - Public API

    func connect(_ bookmark: Bookmark) {
        connect(ConnectionConfiguration(bookmark: bookmark))
    }

    func connect(_ configuration: ConnectionConfiguration) {
        let id = configuration.id
        guard tasks[id] == nil else { return }
        configurationsByID[id] = configuration

        Task { @MainActor in
            let runtime =
                runtimeStores.first(where: { $0.id == id })
                ?? ConnectionRuntime(id: id, connectionController: self)

            if !runtimeStores.contains(where: { $0.id == id }) {
                runtimeStores.append(runtime)
            }
            if let modelContext {
                runtime.attach(modelContext: modelContext)
            }
            runtime.connect()
        }

        let task = Task {
            let maxConnectAttempts = 2

            for attempt in 1...maxConnectAttempts {
                do {
                    let stream = await socketClient.connect(configuration: configuration)

                    await MainActor.run {
                        self.startIdleTimers()
                    }

                    for try await event in stream {
                        await handle(event)
                    }

                    break

                } catch {
                    let shouldRetry =
                        attempt < maxConnectAttempts &&
                        isTransientConnectError(error) &&
                        !Task.isCancelled

                    if shouldRetry {
                        await socketClient.disconnect(id: id)
                        try? await Task.sleep(for: .milliseconds(500))
                        continue
                    }

                    await MainActor.run {
                        if let runtime = runtimeStores.first(where: { $0.id == id }) {
                            runtime.lastError = error
                        }
                    }

                    await socketClient.emit(.disconnected(id, nil, error))
                    break
                }
            }

            // cleanup commun (success OU error)
            await MainActor.run {
                if let runtime = runtimeStores.first(where: { $0.id == id }) {
                    runtime.disconnect()
                }
            }

            tasks[id] = nil
        }

        tasks[id] = task
    }

    func disconnectAll() {
        for (id, task) in tasks {
            task.cancel()
            Task { await socketClient.disconnect(id: id) }
        }
        tasks.removeAll()
    }

    @MainActor
    func attach(modelContext: ModelContext) {
        guard self.modelContext == nil else { return }
        self.modelContext = modelContext
        for runtime in runtimeStores {
            runtime.attach(modelContext: modelContext)
        }
    }
    
    func isConnected(_ bookmark: Bookmark) -> Bool {
        tasks[bookmark.id] != nil
    }

    func isConnected(_ id: UUID) -> Bool {
        tasks[id] != nil
    }

    func disconnect(_ bookmark: Bookmark, runtime: ConnectionRuntime) {
        disconnect(connectionID: bookmark.id, runtime: runtime)
    }

    @MainActor
    func handleIncomingURL(_ url: URL) -> IncomingURLAction? {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "wired3" || scheme == "wired" else {
            return nil
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let host = components.host?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hostWithPort: String = {
            guard !host.isEmpty else { return "" }
            if let port = components.port {
                return "\(host):\(port)"
            }
            return host
        }()

        let loginFromQuery = components.queryItems?.first(where: {
            $0.name.lowercased() == "login" || $0.name.lowercased() == "user"
        })?.value

        let passwordFromQuery = components.queryItems?.first(where: {
            $0.name.lowercased() == "password" || $0.name.lowercased() == "pass"
        })?.value

        let login = (components.user ?? loginFromQuery ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let password = components.password ?? passwordFromQuery ?? ""
        let normalizedRemotePath: String? = {
            let path = components.percentEncodedPath.removingPercentEncoding ?? components.path
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed != "/" else { return nil }
            return trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)"
        }()

        if hostWithPort.isEmpty {
            guard let remotePath = normalizedRemotePath else {
                presentNewConnection()
                return nil
            }

            if let activeConnectionID {
                return IncomingURLAction(connectionID: activeConnectionID, remotePath: remotePath)
            }

            if let connected = runtimeStores.first(where: { $0.status == .connected }) {
                requestedSelectionID = connected.id
                activeConnectionID = connected.id
                return IncomingURLAction(connectionID: connected.id, remotePath: remotePath)
            }

            return nil
        }

        if login.isEmpty {
            presentNewConnection(prefill: NewConnectionDraft(hostname: hostWithPort))
            return nil
        }

        let draft = NewConnectionDraft(
            hostname: hostWithPort,
            login: login,
            password: password
        )
        guard let connectionID = connectOrReuseTemporary(draft) else {
            return nil
        }
        return IncomingURLAction(connectionID: connectionID, remotePath: normalizedRemotePath)
    }

    // MARK: - Event handling

    private func handle(_ event: SocketEvent) async {
        switch event {

        case .connected(let id, let connection):
            await MainActor.run {
                if let runtime = self.runtimeStores.first(where: { $0.id == id }) {
                    runtime.connected(connection)
                }
            }

        case .disconnected(let id, let connection, let error):
            await MainActor.run {
                if let runtime = self.runtimeStores.first(where: { $0.id == id }) {
                    runtime.disconnect(error: error)
                }
            }
            tasks[id] = nil

        case .received(let id, let connection, let message):
            await handleMessage(message, connection: connection, from: id)
        }
    }

    private func isTransientConnectError(_ error: Error) -> Bool {
        let description = error.localizedDescription.lowercased()
        let transientMarkers = [
            "is unreachable",
            "network is unreachable",
            "host is down",
            "no route to host",
            "timed out",
            "operation timed out",
            "connection refused"
        ]

        return transientMarkers.contains { description.contains($0) }
    }

    private func handleMessage(_ message: P7Message, connection: Connection, from id: UUID) async {
        guard let runtime = runtimeStores.first(where: { $0.id == id }) else { return }
                
        switch message.name {
//        case "wired.error":
//            await MainActor.run {
//                runtime.lastError = WiredError(message: message)
//            }
            
        case "wired.login":
            await MainActor.run {
                runtime.userID = message.uint32(forField: "wired.user.id") ?? 0
            }
            
            let request = P7Message(
                withName: "wired.chat.get_chats",
                spec: spec!
            )
            try? await runtime.send(request)
        case "wired.account.privileges":
            var parsedPrivileges: [String: Any] = [:]

            for fieldName in spec?.accountPrivileges ?? [] {
                if let field = spec?.fieldsByName[fieldName] {
                    if field.type == .bool {
                        if let val = message.bool(forField: fieldName) {
                            parsedPrivileges[fieldName] = val
                        }
                    } else if field.type == .enum32 || field.type == .uint32 {
                        if let val = message.uint32(forField: fieldName) {
                            parsedPrivileges[fieldName] = val
                        }
                    }
                }
            }

            if let color = message.enumeration(forField: "wired.account.color")
                ?? message.uint32(forField: "wired.account.color") {
                parsedPrivileges["wired.account.color"] = color
            }

            await MainActor.run {
                runtime.privileges = parsedPrivileges
            }
        case "wired.account.accounts_changed":
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .wiredAccountAccountsChanged,
                    object: nil,
                    userInfo: ["runtimeID": id]
                )
            }

//        case "wired.user.info":
//            await updateUserInfo(from: message, in: runtime)
//            await MainActor.run {
//                runtime.showInfos.toggle()
//            }
        case "wired.server_info":
            print("wired.server_info")
            
        case "wired.chat.chat_list":
            if let chat = await parseChat(from: message) {
                await runtime.appendChat(chat)
                
                if chat.id == 1 {
                    try? await runtime.joinChat(chat.id)
                }
            }
        case "wired.chat.chat_created":
            if let chatID = message.uint32(forField: "wired.chat.id") {
                await MainActor.run {
                    if runtime.chat(withID: chatID) == nil {
                        runtime.appendPrivateChat(
                            Chat(id: chatID, name: "Private Chat", isPrivate: true)
                        )
                    }
                    runtime.selectedChatID = chatID
                }
            }
        case "wired.chat.invitation":
            if let chatID = message.uint32(forField: "wired.chat.id"),
               let inviterUserID = message.uint32(forField: "wired.user.id") {
                await MainActor.run {
                    if runtime.chat(withID: chatID) == nil {
                        runtime.appendPrivateChat(
                            Chat(id: chatID, name: "Private Chat", isPrivate: true)
                        )
                    }

                    let inviterNick =
                        runtime.chats
                        .flatMap(\.users)
                        .first(where: { $0.id == inviterUserID })?
                        .nick

                    runtime.pendingChatInvitation = ChatInvitation(
                        chatID: chatID,
                        inviterUserID: inviterUserID,
                        inviterNick: inviterNick
                    )
                }
            }
            
        case "wired.chat.public_chat_created":
            if let chat = await parseChat(from: message) {
                await runtime.appendChat(chat)
            }

        case "wired.chat.public_chat_deleted":
            if let chatID = message.uint32(forField: "wired.chat.id") {
                await MainActor.run {
                    runtime.chats.removeAll(where: { $0.id == chatID })
                }
            }
            
        case "wired.chat.user_list":
            if let chatID = message.uint32(forField: "wired.chat.id") {
                if let chat = await runtime.chat(withID: chatID) {
                    if let user = await parseUser(from: message) {
                        await MainActor.run {
                            chat.users.append(user)
                            runtime.refreshPrivateChatName(chat)
                        }
                    }
                }
            }
        case "wired.chat.user_list.done":
            if let chatID = message.uint32(forField: "wired.chat.id") {
                await MainActor.run {
                    if let chat = runtime.chat(withID: chatID) {
                        chat.joined = true
                        runtime.refreshPrivateChatName(chat)
                    }
                }
                
                if chatID == 1 {
                    await MainActor.run {
                        runtime.joined = true
                    }
                }
            }
        case "wired.chat.topic":
            if let chatID = message.uint32(forField: "wired.chat.id") {
                if let chat = await runtime.chat(withID: chatID) {
                    if let topic = message.string(forField: "wired.chat.topic.topic"),
                       let nick = message.string(forField: "wired.user.nick"),
                       let time = message.date(forField: "wired.chat.topic.time") {
                        await MainActor.run {
                            chat.topic = Topic(topic: topic, nick: nick, time: time)
                        }
                    }
                }
            }
            
        case "wired.chat.user_join":
            if let chatID = message.uint32(forField: "wired.chat.id") {
                if let chat = await runtime.chat(withID: chatID) {
                    if let user = await parseUser(from: message) {
                        await MainActor.run {
                            chat.users.append(user)
                            chat.messages.append(ChatEvent(chat: chat, user: user, type: .join, text: ""))
                            runtime.refreshPrivateChatName(chat)
                        }
                    }
                }
            }
        case "wired.chat.user_leave":
            if  let chatID = message.uint32(forField: "wired.chat.id"),
                let userID = message.uint32(forField: "wired.user.id")
            {
                if let chat = await runtime.chat(withID: chatID) {
                    await MainActor.run {
                        if let user = chat.users.first(where: { $0.id == userID }) {
                            chat.messages.append(ChatEvent(chat: chat, user: user, type: .leave, text: ""))
                            chat.users.removeAll { $0.id == user.id }
                        }
                        runtime.refreshPrivateChatName(chat)

                        // Keep local joined state authoritative when our own user leaves.
                        if userID == runtime.userID {
                            if chat.isPrivate {
                                runtime.removePrivateChat(chat.id)
                            } else {
                                chat.joined = false
                                if runtime.selectedChatID == chat.id {
                                    runtime.selectedChatID = 1
                                }
                            }
                        }
                    }
                }
            }
        case "wired.chat.user_decline_invitation":
            if let chatID = message.uint32(forField: "wired.chat.id"),
               let userID = message.uint32(forField: "wired.user.id"),
               let chat = await runtime.chat(withID: chatID) {
                await MainActor.run {
                    if let user = chat.users.first(where: { $0.id == userID }) {
                        chat.messages.append(ChatEvent(chat: chat, user: user, type: .leave, text: ""))
                    }
                }
            }
        case "wired.chat.user_status":
            if let userID = message.uint32(forField: "wired.user.id") {
                let targetChatID = message.uint32(forField: "wired.chat.id")

                await MainActor.run {
                    let targetChats: [Chat]
                    if let targetChatID {
                        targetChats = (runtime.chats + runtime.private_chats).filter { $0.id == targetChatID }
                    } else {
                        targetChats = runtime.chats + runtime.private_chats
                    }

                    for chat in targetChats {
                        guard let user = chat.users.first(where: { $0.id == userID }) else { continue }
                        user.nick = message.string(forField: "wired.user.nick") ?? user.nick
                        user.status = message.string(forField: "wired.user.status")
                        user.icon = message.data(forField: "wired.user.icon") ?? user.icon
                        user.idle = message.bool(forField: "wired.user.idle") ?? user.idle
                        user.color = message.enumeration(forField: "wired.account.color")
                            ?? message.uint32(forField: "wired.account.color")
                            ?? user.color
                        runtime.refreshPrivateChatName(chat)
                    }
                }
            }
        case "wired.chat.say":
            if let chatID = message.uint32(forField: "wired.chat.id") {
                if let userID = message.uint32(forField: "wired.user.id") {
                    if let chat = await runtime.chat(withID: chatID) {
                        if let user = await chat.users.first(where: { $0.id == userID }) {
                            if let say = message.string(forField: "wired.chat.say") {
                                await MainActor.run {
                                    chat.messages.append(ChatEvent(chat: chat, user: user, type: .say, text: say))
                                    
                                    if userID != runtime.userID {
                                        chat.unreadMessagesCount += 1
                                        
                                        updateNotificationsBadge()
                                        sendChatNotification(from: user.nick, text: say)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        case "wired.chat.me":
            if let chatID = message.uint32(forField: "wired.chat.id") {
                if let userID = message.uint32(forField: "wired.user.id") {
                    if let chat = await runtime.chat(withID: chatID) {
                        if let user = await chat.users.first(where: { $0.id == userID }) {
                            if let say = message.string(forField: "wired.chat.me") {
                                await MainActor.run {
                                    chat.messages.append(ChatEvent(chat: chat, user: user, type: .me, text: say))
                                    
                                    if userID != runtime.userID {
                                        chat.unreadMessagesCount += 1
                                        
                                        updateNotificationsBadge()
                                        sendChatNotification(from: user.nick, text: say)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        case "wired.message.message":
            if let senderUserID = message.uint32(forField: "wired.user.id"),
               let body = message.string(forField: "wired.message.message") {
                await MainActor.run {
                    guard senderUserID != runtime.userID else { return }
                    runtime.receivePrivateMessage(from: senderUserID, text: body)

                    if runtime.selectedTab != .messages {
                        self.sendMessageNotification(
                            title: "New Private Message",
                            from: runtime.messageConversations.first(where: {
                                $0.kind == .direct && $0.participantUserID == senderUserID
                            })?.title ?? "User",
                            text: body
                        )
                    }
                }
            }
        case "wired.message.broadcast":
            if let senderUserID = message.uint32(forField: "wired.user.id"),
               let body = message.string(forField: "wired.message.broadcast") {
                await MainActor.run {
                    guard senderUserID != runtime.userID else { return }
                    runtime.receiveBroadcastMessage(from: senderUserID, text: body)

                    if runtime.selectedTab != .messages {
                        let nick =
                            runtime.messageConversations
                            .first(where: { $0.kind == .broadcast })?
                            .messages
                            .last(where: { $0.senderUserID == senderUserID })?
                            .senderNick ?? "User"

                        self.sendMessageNotification(
                            title: "New Broadcast",
                            from: nick,
                            text: body
                        )
                    }
                }
            }

        case "wired.file.directory_changed":
            if let path = message.string(forField: "wired.file.path") {
                NotificationCenter.default.post(
                    name: .wiredFileDirectoryChanged,
                    object: RemoteDirectoryEvent(connectionID: id, path: path)
                )
            }

        case "wired.file.directory_deleted":
            if let path = message.string(forField: "wired.file.path") {
                NotificationCenter.default.post(
                    name: .wiredFileDirectoryDeleted,
                    object: RemoteDirectoryEvent(connectionID: id, path: path)
                )
            }

        default:
            break
        }
    }
    
    
    // MARK: -
    @MainActor private func parseChat(from message: P7Message) -> Chat? {
        guard
            let id = message.uint32(forField: "wired.chat.id"),
            let name = message.string(forField: "wired.chat.name")
        else {
            return nil
        }

        return .init(
            id: id,
            name: name
        )
    }
    
    @MainActor private func parseUser(from message: P7Message) -> User? {
        guard
            let id = message.uint32(forField: "wired.user.id"),
            let nick = message.string(forField: "wired.user.nick"),
            let icon = message.data(forField: "wired.user.icon"),
            let idle = message.bool(forField: "wired.user.idle")
        else {
            return nil
        }
        
        let user = User(
            id: id,
            nick: nick,
            status: message.string(forField: "wired.user.status"),
            icon: icon,
            idle: idle,
        )

        user.color = message.enumeration(forField: "wired.account.color")
            ?? message.uint32(forField: "wired.account.color")
            ?? 0

        return user
    }

    @MainActor public func updateUserInfo(from message: P7Message, in runtime: ConnectionRuntime) async {
        if let userID = message.uint32(forField: "wired.user.id") {
            for chat in runtime.chats {
                if let user = chat.users.first(where: { $0.id == userID }) {
                    if let login = message.string(forField: "wired.user.login") {
                        await MainActor.run {
                            user.login = login
                        }
                    }
                    
                    if let ip = message.string(forField: "wired.user.ip") {
                        await MainActor.run {
                            user.ipAddress = ip
                        }
                    }
                    
                    if let host = message.string(forField: "wired.user.host") {
                        await MainActor.run {
                            user.host = host
                        }
                    }
                    
                    if let cipherName = message.string(forField: "wired.user.cipher.name") {
                        await MainActor.run {
                            user.cipherName = cipherName
                        }
                    }
                    
                    if let cipherBits = message.string(forField: "wired.user.cipher.bits") {
                        await MainActor.run {
                            user.cipherBits = cipherBits
                        }
                    }
                    
                    if let appVersion = message.string(forField: "wired.info.application.version") {
                        await MainActor.run {
                            user.appVersion = appVersion
                        }
                    }
                    
                    if let appBuild = message.string(forField: "wired.info.application.build") {
                        await MainActor.run {
                            user.appBuild = appBuild
                        }
                    }
                    
                    if let osName = message.string(forField: "wired.info.os.name") {
                        await MainActor.run {
                            user.osName = osName
                        }
                    }
                    
                    if let osVersion = message.string(forField: "wired.info.os.version") {
                        await MainActor.run {
                            user.osVersion = osVersion
                        }
                    }
                    
                    if let arch = message.string(forField: "wired.info.arch") {
                        await MainActor.run {
                            user.arch = arch
                        }
                    }
                    
                    if let loginTime = message.date(forField: "wired.user.login_time") {
                        await MainActor.run {
                            user.loginTime = loginTime
                        }
                    }
                    
                    if let idleTime = message.date(forField: "wired.user.idle_time") {
                        await MainActor.run {
                            user.idleTime = idleTime
                        }
                    }
                }
            }
        }
    }
    
    // MARK: -
    
    private func sendChatNotification(from nick: String, text:String) {
        sendMessageNotification(title: "New message", from: nick, text: text)
    }

    private func sendMessageNotification(title: String, from nick: String, text: String) {
        let content = UNMutableNotificationContent()
            content.title = title
            content.subtitle = nick
            content.body = text
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil // immédiat
            )

            UNUserNotificationCenter.current().add(request)
    }
    
    @MainActor public func updateNotificationsBadge() {
        let count = runtimeStores.reduce(0) {
            $0 + $1.totalUnreadMessages
        }

        UNUserNotificationCenter.current().setBadgeCount(count)

        #if os(macOS)
        NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
        #endif
    }
}
