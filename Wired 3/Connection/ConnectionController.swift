//
//  ConnectionController.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 18/12/2025.
//  Copyright © 2025 Read-Write. All rights reserved.
//

import SwiftUI
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

@Observable
final class ConnectionController {

    // MARK: - Dependencies

    let socketClient: SocketClient
    var runtimeStores: [ConnectionRuntime] = []
    var connectionEvents: [SocketEvent] = []
    
    // MARK: - Runtime

    private var tasks: [UUID: Task<Void, Never>] = [:]

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
        guard tasks[bookmark.id] == nil else { return }

        let id = bookmark.id

        Task { @MainActor in
            let runtime =
                runtimeStores.first(where: { $0.id == id })
                ?? ConnectionRuntime(id: id, connectionController: self)

            runtimeStores.append(runtime)
            runtime.connect()
        }

        let task = Task {
            let maxConnectAttempts = 2

            for attempt in 1...maxConnectAttempts {
                do {
                    let stream = await socketClient.connect(bookmark: bookmark)

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

    func disconnect(_ bookmark: Bookmark, runtime: ConnectionRuntime) {
        tasks[bookmark.id]?.cancel()
        tasks[bookmark.id] = nil

        Task {
            await socketClient.disconnect(id: bookmark.id)
            
            await MainActor.run {
                runtime.disconnect(error: nil)
            }
        }
    }

    func disconnectAll() {
        for (id, task) in tasks {
            task.cancel()
            Task { await socketClient.disconnect(id: id) }
        }
        tasks.removeAll()
    }
    
    func isConnected(_ bookmark: Bookmark) -> Bool {
        tasks[bookmark.id] != nil
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
                    } else if field.type == .uint32 {
                        if let val = message.uint32(forField: fieldName) {
                            parsedPrivileges[fieldName] = val
                        }
                    }
                }
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
                if let chat = await runtime.chats.first(where: { $0.id == chatID }) {
                    if let user = await parseUser(from: message) {
                        await MainActor.run {
                            chat.users.append(user)
                        }
                    }
                }
            }
        case "wired.chat.user_list.done":
            if let chatID = message.uint32(forField: "wired.chat.id") {
                await MainActor.run {
                    runtime.chats.first(where: { $0.id == chatID })?.joined.toggle()
                }
                
                if chatID == 1 {
                    await MainActor.run {
                        runtime.joined = true
                    }
                }
            }
        case "wired.chat.topic":
            if let chatID = message.uint32(forField: "wired.chat.id") {
                if let chat = await runtime.chats.first(where: { $0.id == chatID }) {
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
                if let chat = await runtime.chats.first(where: { $0.id == chatID }) {
                    if let user = await parseUser(from: message) {
                        await MainActor.run {
                            chat.users.append(user)
                            chat.messages.append(ChatEvent(chat: chat, user: user, type: .join, text: ""))
                        }
                    }
                }
            }
        case "wired.chat.user_leave":
            if  let chatID = message.uint32(forField: "wired.chat.id"),
                let userID = message.uint32(forField: "wired.user.id")
            {
                if let chat = await runtime.chats.first(where: { $0.id == chatID }) {
                    if let user = await chat.users.first(where: { $0.id == userID }) {
                        await MainActor.run {
                            chat.messages.append(ChatEvent(chat: chat, user: user, type: .leave, text: ""))
                            chat.users.removeAll { $0.id == user.id }
                        }
                    }
                }
            }
        case "wired.chat.user_status":
            if let userID = message.uint32(forField: "wired.user.id") {
                let targetChatID = message.uint32(forField: "wired.chat.id")

                await MainActor.run {
                    let targetChats: [Chat]
                    if let targetChatID {
                        targetChats = runtime.chats.filter { $0.id == targetChatID }
                    } else {
                        targetChats = runtime.chats
                    }

                    for chat in targetChats {
                        guard let user = chat.users.first(where: { $0.id == userID }) else { continue }
                        user.nick = message.string(forField: "wired.user.nick") ?? user.nick
                        user.status = message.string(forField: "wired.user.status")
                        user.icon = message.data(forField: "wired.user.icon") ?? user.icon
                        user.idle = message.bool(forField: "wired.user.idle") ?? user.idle
                    }
                }
            }
        case "wired.chat.say":
            if let chatID = message.uint32(forField: "wired.chat.id") {
                if let userID = message.uint32(forField: "wired.user.id") {
                    if let chat = await runtime.chats.first(where: { $0.id == chatID }) {
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
                    if let chat = await runtime.chats.first(where: { $0.id == chatID }) {
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
        
        return .init(
            id: id,
            nick: nick,
            status: message.string(forField: "wired.user.status"),
            icon: icon,
            idle: idle,
        )
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
        let content = UNMutableNotificationContent()
            content.title = "New message from \(nick)"
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
            $0 + $1.totalUnreadChatMessages
        }

        UNUserNotificationCenter.current().setBadgeCount(count)

        #if os(macOS)
        NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
        #endif
    }
}
