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

            let request = P7Message(withName: "wired.chat.get_chats", spec: spec!)
            try? await runtime.send(request)

            try? await runtime.subscribeBoards()
            try? await runtime.getBoards()
        case "wired.account.privileges":
            await MainActor.run {
                runtime.privileges = [:]
            }
            
            for fieldName in spec?.accountPrivileges ?? [] {
                if let field = spec?.fieldsByName[fieldName] {
                    if field.type == .bool {
                        if let val = message.bool(forField: fieldName) {
                            await MainActor.run {
                                runtime.privileges[fieldName] = val
                            }
                        }
                    } else if field.type == .uint32 {
                        if let val = message.uint32(forField: fieldName) {
                            await MainActor.run {
                                runtime.privileges[fieldName] = val
                            }
                        }
                    }
                }
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

        // MARK: - Board list (initial load)

        case "wired.board.board_list":
            guard let path = message.string(forField: "wired.board.board") else { break }
            let readable = message.bool(forField: "wired.board.readable") ?? true
            let writable  = message.bool(forField: "wired.board.writable") ?? false
            await MainActor.run {
                let board = Board(path: path, readable: readable, writable: writable)
                runtime.appendBoard(board)
            }

        case "wired.board.board_list.done":
            await MainActor.run { runtime.boardsLoaded = true }

        // MARK: - Thread list

        case "wired.board.thread_list":
            guard
                let boardPath = message.string(forField: "wired.board.board"),
                let uuid      = message.uuid(forField: "wired.board.thread"),
                let subject   = message.string(forField: "wired.board.subject"),
                let nick      = message.string(forField: "wired.user.nick"),
                let postDate  = message.date(forField: "wired.board.post_date")
            else { break }
            let replies = Int(message.uint32(forField: "wired.board.replies") ?? 0)
            let isOwn   = message.bool(forField: "wired.board.own_thread") ?? false
            let lastReplyDate = message.date(forField: "wired.board.latest_reply_date")
            await MainActor.run {
                if let board = runtime.boardsByPath[boardPath] {
                    let thread = BoardThread(uuid: uuid, boardPath: boardPath,
                                            subject: subject, nick: nick,
                                            postDate: postDate, replies: replies, isOwn: isOwn)
                    thread.lastReplyDate = lastReplyDate
                    thread.lastReplyUUID = message.uuid(forField: "wired.board.latest_reply")
                    board.threads.append(thread)
                }
            }

        case "wired.board.thread_list.done":
            break   // view can observe board.threads directly

        // MARK: - Thread content (first post + replies)

        case "wired.board.thread":
            guard
                let threadUUID = message.uuid(forField: "wired.board.thread"),
                let text       = message.string(forField: "wired.board.text")
            else { break }
            await MainActor.run {
                if let thread = runtime.thread(uuid: threadUUID) {
                    let post = BoardPost(uuid: threadUUID, threadUUID: threadUUID,
                                        text: text, nick: thread.nick,
                                        postDate: thread.postDate,
                                        icon: message.data(forField: "wired.user.icon"))
                    thread.posts = [post]
                }
            }

        case "wired.board.post_list":
            guard
                let postUUID   = message.uuid(forField: "wired.board.post"),
                let threadUUID = message.uuid(forField: "wired.board.thread"),
                let text       = message.string(forField: "wired.board.text"),
                let nick       = message.string(forField: "wired.user.nick"),
                let postDate   = message.date(forField: "wired.board.post_date")
            else { break }
            let isOwn = message.bool(forField: "wired.board.own_post") ?? false
            await MainActor.run {
                if let thread = runtime.thread(uuid: threadUUID) {
                    let post = BoardPost(uuid: postUUID, threadUUID: threadUUID,
                                        text: text, nick: nick, postDate: postDate,
                                        icon: message.data(forField: "wired.user.icon"),
                                        isOwn: isOwn)
                    if let editDate = message.date(forField: "wired.board.edit_date") {
                        post.editDate = editDate
                    }
                    thread.posts.append(post)
                }
            }

        case "wired.board.post_list.done":
            if let threadUUID = message.uuid(forField: "wired.board.thread") {
                await MainActor.run {
                    runtime.thread(uuid: threadUUID)?.postsLoaded = true
                }
            }

        // MARK: - Live board events

        case "wired.board.board_added":
            guard let path = message.string(forField: "wired.board.board") else { break }
            let readable = message.bool(forField: "wired.board.readable") ?? true
            let writable  = message.bool(forField: "wired.board.writable") ?? false
            await MainActor.run {
                guard runtime.boardsByPath[path] == nil else { return }
                let board = Board(path: path, readable: readable, writable: writable)
                runtime.appendBoard(board)
            }

        case "wired.board.board_deleted":
            guard let path = message.string(forField: "wired.board.board") else { break }
            await MainActor.run {
                runtime.boardsByPath.removeValue(forKey: path)
                runtime.boards.removeAll { $0.path == path }
                for board in runtime.boardsByPath.values {
                    board.children?.removeAll { $0.path == path }
                }
            }

        case "wired.board.board_renamed", "wired.board.board_moved":
            guard
                let oldPath = message.string(forField: "wired.board.board"),
                let newPath = message.string(forField: "wired.board.new_board")
            else { break }
            await MainActor.run {
                if let board = runtime.boardsByPath.removeValue(forKey: oldPath) {
                    board.path = newPath
                    runtime.boardsByPath[newPath] = board
                }
            }

        case "wired.board.board_info":
            guard let path = message.string(forField: "wired.board.board") else { break }
            await MainActor.run {
                runtime.boardsByPath[path]?.apply(message)
            }

        case "wired.board.board_info_changed":
            guard let path = message.string(forField: "wired.board.board") else { break }
            await MainActor.run {
                if let board = runtime.boardsByPath[path] {
                    if let r = message.bool(forField: "wired.board.readable") { board.readable = r }
                    if let w = message.bool(forField: "wired.board.writable") { board.writable = w }
                }
            }

        // MARK: - Live thread events

        case "wired.board.thread_added":
            guard
                let boardPath = message.string(forField: "wired.board.board"),
                let uuid      = message.uuid(forField: "wired.board.thread"),
                let subject   = message.string(forField: "wired.board.subject"),
                let nick      = message.string(forField: "wired.user.nick"),
                let postDate  = message.date(forField: "wired.board.post_date")
            else { break }
            await MainActor.run {
                if let board = runtime.boardsByPath[boardPath] {
                    guard !board.threads.contains(where: { $0.uuid == uuid }) else { return }
                    let thread = BoardThread(uuid: uuid, boardPath: boardPath,
                                            subject: subject, nick: nick,
                                            postDate: postDate,
                                            isOwn: message.bool(forField: "wired.board.own_thread") ?? false)
                    board.threads.append(thread)
                }
            }

        case "wired.board.thread_changed":
            guard let uuid = message.uuid(forField: "wired.board.thread") else { break }
            await MainActor.run {
                runtime.thread(uuid: uuid)?.apply(message)
            }

        case "wired.board.thread_moved":
            guard
                let uuid        = message.uuid(forField: "wired.board.thread"),
                let newBoardPath = message.string(forField: "wired.board.new_board")
            else { break }
            await MainActor.run {
                if let thread = runtime.thread(uuid: uuid) {
                    runtime.boardsByPath[thread.boardPath]?.threads.removeAll { $0.uuid == uuid }
                    thread.boardPath = newBoardPath
                    runtime.boardsByPath[newBoardPath]?.threads.append(thread)
                }
            }

        case "wired.board.thread_deleted":
            guard let uuid = message.uuid(forField: "wired.board.thread") else { break }
            await MainActor.run {
                if let thread = runtime.thread(uuid: uuid) {
                    runtime.boardsByPath[thread.boardPath]?.threads.removeAll { $0.uuid == uuid }
                }
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
