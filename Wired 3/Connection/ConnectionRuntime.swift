//
//  ConnectionRuntime.swift
//  Wired-macOS
//
//  Created by Rafaël Warnault on 19/12/2025.
//  Copyright © 2025 Read-Write. All rights reserved.
//

import SwiftUI
import SwiftData
import WiredSwift

struct ChatInvitation: Equatable {
    let chatID: UInt32
    let inviterUserID: UInt32
    let inviterNick: String?
}

enum MessageConversationKind {
    case direct
    case broadcast
}

@Observable
@MainActor
final class MessageEvent: Identifiable {
    let id: UUID
    let senderNick: String
    let senderUserID: UInt32?
    let senderIcon: Data?
    let text: String
    let date: Date
    let isFromCurrentUser: Bool

    init(
        id: UUID = UUID(),
        senderNick: String,
        senderUserID: UInt32?,
        senderIcon: Data?,
        text: String,
        date: Date = Date(),
        isFromCurrentUser: Bool
    ) {
        self.id = id
        self.senderNick = senderNick
        self.senderUserID = senderUserID
        self.senderIcon = senderIcon
        self.text = text
        self.date = date
        self.isFromCurrentUser = isFromCurrentUser
    }
}

@Observable
@MainActor
final class MessageConversation: Identifiable {
    let id: UUID
    let kind: MessageConversationKind
    var title: String
    var participantNick: String?
    var participantUserID: UInt32?
    var messages: [MessageEvent] = []
    var unreadMessagesCount: Int = 0

    var lastMessageDate: Date? {
        messages.last?.date
    }

    init(
        id: UUID = UUID(),
        kind: MessageConversationKind,
        title: String,
        participantNick: String? = nil,
        participantUserID: UInt32? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.participantNick = participantNick
        self.participantUserID = participantUserID
    }
}

@Observable
@MainActor
final class ConnectionRuntime: Identifiable {
    let id: UUID
    let connectionController: ConnectionController
    
    var connection : Connection? = nil
    
    var selectedTab: MainTab = .chats
    var selectedChatID: UInt32? = 1
    var userID: UInt32 = 0
    var privileges: [String: Any] = [:]
    
    var status: Status = .disconnected
    var joined = false
    var lastError: Error?
    var hasConnectionIssue: Bool = false
    var isAutoReconnectScheduled: Bool = false
    var autoReconnectAttempt: Int = 0
    var autoReconnectInterval: TimeInterval = 0
    var autoReconnectNextAttemptAt: Date? = nil

    let idleTimeout = 10.0
    var lastMessageSentAt: Date = .now
    private(set) var isIdle: Bool = false
    private var timerTask: Task<Void, Never>?
    private var didLoadPersistedMessages: Bool = false
    private var modelContext: ModelContext?
    
    var serverInfo: P7Message? = nil
    var chats: [Chat] = []
    var private_chats: [Chat] = []

    var pendingChatInvitation: ChatInvitation? = nil
    var selectedMessageConversationID: UUID? = nil
    var messageConversations: [MessageConversation] = []

    // Boards
    var boards: [Board] = []
    @ObservationIgnored
    var boardsByPath: [String: Board] = [:]
    @ObservationIgnored
    private var pendingLocalPostUUIDByThread: [String: String] = [:]
    var boardsLoaded: Bool = false
    var selectedBoardPath: String?
    var selectedThreadUUID: String?
    
    var showInfos: Bool = false
    var showInfosUserID: UInt32 = 0
        
    private let defaults = UserDefaults.standard

    var substituteEmoji: Bool {
        defaults.bool(forKey: "SubstituteEmoji")
    }
    
    var totalUnreadMessages: Int {
        totalUnreadChatMessages + totalUnreadPrivateMessages
    }

    var totalUnreadBoardPosts: Int {
        boards.reduce(0) { $0 + $1.unreadPostsCount }
    }

    var totalUnreadNotifications: Int {
        totalUnreadMessages + totalUnreadBoardPosts
    }
    
    var totalUnreadChatMessages: Int {
        (chats + private_chats).reduce(0) { $0 + $1.unreadMessagesCount }
    }

    var totalUnreadPrivateMessages: Int {
        messageConversations.reduce(0) { $0 + $1.unreadMessagesCount }
    }

    var currentNick: String? {
        (chats + private_chats)
            .flatMap(\.users)
            .first(where: { $0.id == userID })?
            .nick
    }
    
    enum Status {
        case disconnected
        case connecting
        case connected
    }
    
    
    // MARK: -
    
    init(id: UUID, connectionController: ConnectionController) {
        self.id = id
        self.connectionController = connectionController
    }

    func attach(modelContext: ModelContext) {
        guard self.modelContext == nil else { return }
        self.modelContext = modelContext
        loadPersistedMessagesIfNeeded()
    }
    

    // MARK: - Connection State

    func connect() {
        lastError = nil
        hasConnectionIssue = false
        privileges = [:]
        userID = 0
        status = .connecting
        resetAutoReconnectState()
        loadPersistedMessagesIfNeeded()
    }

    func connected(_ connection: Connection) {
        self.connection = connection
        lastError = nil
        hasConnectionIssue = false
        status = .connected
        resetAutoReconnectState()
    }

    func disconnect(error: Error? = nil) {
        let previousStatus = status
        joined = false
        privileges = [:]
        userID = 0
        status = .disconnected
        pendingChatInvitation = nil
        
        if let error {
            lastError = error
            hasConnectionIssue = true
        } else if previousStatus == .connected {
            // Explicit/manual disconnect from a healthy state should not keep warning state.
            lastError = nil
            hasConnectionIssue = false
        }
        
        resetChats()
        resetBoards()
    }

    func setAutoReconnectState(
        isScheduled: Bool,
        attempt: Int = 0,
        interval: TimeInterval = 0,
        nextAttemptAt: Date? = nil
    ) {
        isAutoReconnectScheduled = isScheduled
        autoReconnectAttempt = attempt
        autoReconnectInterval = interval
        autoReconnectNextAttemptAt = nextAttemptAt
    }

    func resetAutoReconnectState() {
        isAutoReconnectScheduled = false
        autoReconnectAttempt = 0
        autoReconnectInterval = 0
        autoReconnectNextAttemptAt = nil
    }
    
    // MARK: - Idle Timer
    
    private func evaluateIdleState() {
        let elapsed = Date.now.timeIntervalSince(lastMessageSentAt)
                
        if elapsed >= idleTimeout, !isIdle {
            isIdle = true
            
            let message = P7Message(withName: "wired.user.set_idle", spec: spec!)
            
            Task {
                try? await connectionController.socketClient.send(message, on: id)
            }
        }
    }
    
    func startIdleTimer() {
        stopIdleTimer()

        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                
                evaluateIdleState()
            }
        }
    }

    func stopIdleTimer() {
        timerTask?.cancel()
        timerTask = nil
    }


    

    // MARK: - Chat Models
    
    func resetChats() {
        chats = []
        private_chats = []
    }

    func resetMessages() {
        selectedMessageConversationID = nil
        messageConversations = []
        persistMessages()
    }

    // MARK: - Board Models

    func resetBoards() {
        boards = []
        boardsByPath = [:]
        boardsLoaded = false
        selectedBoardPath = nil
        selectedThreadUUID = nil
        connectionController.updateNotificationsBadge()
    }

    func appendBoard(_ board: Board) {
        let parentPath = board.parentPath
        if parentPath.isEmpty || parentPath == "/" {
            boards.append(board)
        } else if let parent = boardsByPath[parentPath] {
            if parent.children == nil { parent.children = [] }
            parent.children!.append(board)
        }
        boardsByPath[board.path] = board
    }
    
    /// Pending path remaps from in-place board moves/renames.
    /// The view reads and clears these to update expansion state.
    @ObservationIgnored
    var pendingBoardPathRemaps: [(from: String, to: String)] = []

    /// Move or rename a board in-place without tearing down the tree.
    func moveBoardInTree(from oldPath: String, to newPath: String) {
        guard oldPath != newPath else { return }

        // If the board was already moved (e.g. child notification after parent),
        // check if it's already at the new path — nothing to do.
        guard let board = boardsByPath[oldPath] else {
            if boardsByPath[newPath] != nil { return } // already processed
            // Board not found at old or new path — full re-sync needed
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.resetBoards()
                try? await self.getBoards()
            }
            return
        }

        let oldParentPath = (oldPath as NSString).deletingLastPathComponent
        let newParentPath = (newPath as NSString).deletingLastPathComponent

        // Collect all boards in the subtree (root + descendants)
        let affectedPaths = boardsByPath.keys
            .filter { $0 == oldPath || $0.hasPrefix(oldPath + "/") }
            .sorted()

        // 1. Remove from old parent
        if oldParentPath.isEmpty || oldParentPath == "/" {
            boards.removeAll { $0.path == oldPath }
        } else {
            boardsByPath[oldParentPath]?.children?.removeAll { $0.path == oldPath }
        }

        // 2. Update paths for the moved board and all its descendants
        for affectedPath in affectedPaths {
            guard let affectedBoard = boardsByPath[affectedPath] else { continue }
            let suffix = String(affectedPath.dropFirst(oldPath.count))
            let updatedPath = newPath + suffix

            boardsByPath.removeValue(forKey: affectedPath)
            affectedBoard.path = updatedPath
            boardsByPath[updatedPath] = affectedBoard

            for thread in affectedBoard.threads {
                thread.boardPath = updatedPath
            }

            pendingBoardPathRemaps.append((from: affectedPath, to: updatedPath))
        }

        // 3. Add to new parent (with fallback to root if parent not found)
        if newParentPath.isEmpty || newParentPath == "/" {
            boards.append(board)
        } else if let newParent = boardsByPath[newParentPath] {
            if newParent.children == nil { newParent.children = [] }
            newParent.children!.append(board)
        } else {
            // New parent not yet in tree (out-of-order notification) — park at root
            // so the board stays visible; a subsequent move will place it correctly.
            boards.append(board)
        }
    }

    func board(path: String) -> Board? {
        boardsByPath[path]
    }

    func thread(uuid: String) -> BoardThread? {
        for board in boardsByPath.values {
            if let t = board.threads.first(where: { $0.uuid == uuid }) { return t }
        }
        return nil
    }

    func thread(boardPath: String, uuid: String) -> BoardThread? {
        board(path: boardPath)?.threads.first(where: { $0.uuid == uuid })
    }

    func markThreadAsRead(_ thread: BoardThread) {
        thread.unreadPostsCount = 0
        thread.lastReadAt = .now
        for post in thread.posts {
            post.isUnread = false
        }
        connectionController.updateNotificationsBadge()
    }

    func markThreadAsRead(boardPath: String, threadUUID: String) {
        guard let thread = thread(boardPath: boardPath, uuid: threadUUID) else { return }
        markThreadAsRead(thread)
    }

    func markThreadAsUnread(_ thread: BoardThread) {
        let anchorDate = thread.lastReplyDate ?? thread.postDate
        thread.lastReadAt = anchorDate.addingTimeInterval(-1)
        thread.unreadPostsCount = max(1, thread.unreadPostsCount)

        if thread.postsLoaded {
            for post in thread.posts {
                post.isUnread = post.postDate > (thread.lastReadAt ?? .distantPast)
            }

            if !thread.posts.contains(where: { $0.isUnread }), let lastPost = thread.posts.last {
                lastPost.isUnread = true
            }
        }

        connectionController.updateNotificationsBadge()
    }

    func markThreadHasUnread(_ thread: BoardThread, increment: Int = 1) {
        guard increment > 0 else { return }
        thread.unreadPostsCount += increment
        connectionController.updateNotificationsBadge()
    }

    func refreshPostUnreadState(for thread: BoardThread) {
        guard let lastReadAt = thread.lastReadAt else {
            for post in thread.posts {
                post.isUnread = false
            }
            return
        }

        var unreadCount = 0
        for post in thread.posts {
            let unread = post.postDate > lastReadAt
            post.isUnread = unread
            if unread {
                unreadCount += 1
            }
        }
        thread.unreadPostsCount = unreadCount
        connectionController.updateNotificationsBadge()
    }

    func appendChat(_ chat: Chat) {
        chats.append(chat)
    }

    func appendPrivateChat(_ chat: Chat) {
        guard private_chats.contains(where: { $0.id == chat.id }) == false else { return }
        private_chats.append(chat)
    }

    func removePrivateChat(_ chatID: UInt32) {
        private_chats.removeAll { $0.id == chatID }

        if selectedChatID == chatID {
            selectedChatID = 1
        }
    }

    func chat(withID chatID: UInt32) -> Chat? {
        if let chat = chats.first(where: { $0.id == chatID }) {
            return chat
        }

        return private_chats.first(where: { $0.id == chatID })
    }

    // MARK: - Messages

    func messageConversation(withID conversationID: UUID?) -> MessageConversation? {
        guard let conversationID else { return nil }
        return messageConversations.first(where: { $0.id == conversationID })
    }

    func ensureBroadcastConversation() -> MessageConversation {
        if let conversation = messageConversations.first(where: { $0.kind == .broadcast }) {
            return conversation
        }

        let conversation = MessageConversation(
            kind: .broadcast,
            title: "Broadcasts"
        )
        messageConversations.append(conversation)
        sortMessageConversations()
        persistMessages()
        return conversation
    }

    func openPrivateMessageConversation(with user: User) -> MessageConversation {
        let conversation = ensureDirectConversation(
            nick: user.nick,
            userID: user.id
        )
        selectedMessageConversationID = conversation.id
        selectedTab = .messages
        resetUnreads(conversation)
        persistMessages()
        return conversation
    }

    func ensureDirectConversation(
        nick: String,
        userID: UInt32?
    ) -> MessageConversation {
        if let conversation = messageConversations.first(where: {
            $0.kind == .direct && $0.participantNick == nick
        }) {
            if let userID {
                conversation.participantUserID = userID
            }
            return conversation
        }

        let conversation = MessageConversation(
            kind: .direct,
            title: nick,
            participantNick: nick,
            participantUserID: userID
        )
        messageConversations.append(conversation)
        sortMessageConversations()
        persistMessages()
        return conversation
    }

    func sendPrivateMessage(_ text: String, in conversation: MessageConversation) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard conversation.kind == .direct else { return }

        guard let recipientUserID = resolvedRecipientUserID(for: conversation) else {
            throw WiredError(withTitle: "Private Message", message: "User is offline.")
        }

        let message = P7Message(withName: "wired.message.send_message", spec: spec!)
        message.addParameter(field: "wired.user.id", value: recipientUserID)
        message.addParameter(field: "wired.message.message", value: trimmed)

        if let response = try await send(message), response.name == "wired.error" {
            throw WiredError(message: response)
        }

        appendOwnPrivateMessage(trimmed, to: conversation)
    }

    func sendBroadcastMessage(_ text: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let message = P7Message(withName: "wired.message.send_broadcast", spec: spec!)
        message.addParameter(field: "wired.message.broadcast", value: trimmed)

        if let response = try await send(message), response.name == "wired.error" {
            throw WiredError(message: response)
        }

        let conversation = ensureBroadcastConversation()
        appendOwnMessage(trimmed, to: conversation, isBroadcast: true)
    }

    func receivePrivateMessage(from userID: UInt32, text: String) {
        let sender = onlineUser(withID: userID)
        let nick = sender?.nick ?? "User #\(userID)"
        let icon = sender?.icon
        let conversation = ensureDirectConversation(
            nick: nick,
            userID: userID
        )
        appendIncomingMessage(
            text,
            fromNick: nick,
            userID: userID,
            icon: icon,
            to: conversation
        )
    }

    func receiveBroadcastMessage(from userID: UInt32, text: String) {
        let sender = onlineUser(withID: userID)
        let nick = sender?.nick ?? "User #\(userID)"
        let icon = sender?.icon
        let conversation = ensureBroadcastConversation()
        appendIncomingMessage(
            text,
            fromNick: nick,
            userID: userID,
            icon: icon,
            to: conversation
        )
    }

    func resetUnreads(_ conversation: MessageConversation) {
        conversation.unreadMessagesCount = 0
        connectionController.updateNotificationsBadge()
        persistMessages()
    }

    func canSendMessage(to conversation: MessageConversation) -> Bool {
        switch conversation.kind {
        case .broadcast:
            return hasPrivilege("wired.account.message.broadcast")
        case .direct:
            guard hasPrivilege("wired.account.message.send_messages") else { return false }
            return resolvedRecipientUserID(for: conversation) != nil
        }
    }

    func onlineUser(for conversation: MessageConversation) -> User? {
        guard conversation.kind == .direct else { return nil }

        if let knownID = conversation.participantUserID,
           let user = onlineUser(withID: knownID) {
            if let nick = conversation.participantNick {
                if user.nick == nick {
                    return user
                }
            } else {
                return user
            }
        }

        if let nick = conversation.participantNick {
            return (chats + private_chats)
                .flatMap(\.users)
                .first(where: { $0.nick == nick })
        }

        return nil
    }

    func messageConversationIcon(for conversation: MessageConversation) -> Data? {
        onlineUser(for: conversation)?.icon
    }

    private func appendOwnPrivateMessage(_ text: String, to conversation: MessageConversation) {
        appendOwnMessage(text, to: conversation, isBroadcast: false)
    }

    private func appendOwnMessage(_ text: String, to conversation: MessageConversation, isBroadcast: Bool) {
        let me = onlineUser(withID: userID)
        let nick = me?.nick ?? "You"
        let icon = me?.icon
        conversation.messages.append(
            MessageEvent(
                senderNick: nick,
                senderUserID: userID,
                senderIcon: icon,
                text: text,
                isFromCurrentUser: true
            )
        )
        selectedMessageConversationID = conversation.id
        resetUnreads(conversation)
        sortMessageConversations()
        if selectedTab != .messages && !isBroadcast {
            connectionController.updateNotificationsBadge()
        }
        persistMessages()
    }

    private func appendIncomingMessage(
        _ text: String,
        fromNick nick: String,
        userID: UInt32,
        icon: Data?,
        to conversation: MessageConversation
    ) {
        conversation.messages.append(
            MessageEvent(
                senderNick: nick,
                senderUserID: userID,
                senderIcon: icon,
                text: text,
                isFromCurrentUser: false
            )
        )

        let isSelected = selectedTab == .messages && selectedMessageConversationID == conversation.id
        if !isSelected {
            conversation.unreadMessagesCount += 1
        }

        sortMessageConversations()
        connectionController.updateNotificationsBadge()
        persistMessages()
    }

    private func sortMessageConversations() {
        messageConversations.sort {
            let leftDate = $0.lastMessageDate ?? .distantPast
            let rightDate = $1.lastMessageDate ?? .distantPast
            if leftDate != rightDate {
                return leftDate > rightDate
            }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    // MARK: - Message Persistence

    private func loadPersistedMessagesIfNeeded() {
        guard !didLoadPersistedMessages else { return }
        guard modelContext != nil else { return }
        didLoadPersistedMessages = true
        loadPersistedMessages()
    }

    private func loadPersistedMessages() {
        guard let modelContext else { return }
        guard let key = persistenceKey() else { return }

        do {
            let privateDescriptor = FetchDescriptor<StoredPrivateConversation>(
                predicate: #Predicate<StoredPrivateConversation> { $0.connectionKey == key }
            )
            let storedPrivateConversations = try modelContext.fetch(privateDescriptor)
            let restoredPrivateConversations = storedPrivateConversations.map { storedConversation in
                let conversation = MessageConversation(
                    id: storedConversation.conversationID,
                    kind: .direct,
                    title: storedConversation.title,
                    participantNick: storedConversation.participantNick,
                    participantUserID: storedConversation.participantUserID
                )
                conversation.unreadMessagesCount = storedConversation.unreadMessagesCount
                conversation.messages = storedConversation.messages
                    .sorted(by: { $0.date < $1.date })
                    .map { storedMessage in
                        MessageEvent(
                            id: storedMessage.eventID,
                            senderNick: storedMessage.senderNick,
                            senderUserID: storedMessage.senderUserID,
                            senderIcon: storedMessage.senderIcon,
                            text: storedMessage.text,
                            date: storedMessage.date,
                            isFromCurrentUser: storedMessage.isFromCurrentUser
                        )
                    }
                return conversation
            }

            let broadcastDescriptor = FetchDescriptor<StoredBroadcastConversation>(
                predicate: #Predicate<StoredBroadcastConversation> { $0.connectionKey == key }
            )
            let storedBroadcastConversations = try modelContext.fetch(broadcastDescriptor)
            let restoredBroadcastConversations = storedBroadcastConversations.map { storedConversation in
                let conversation = MessageConversation(
                    id: storedConversation.conversationID,
                    kind: .broadcast,
                    title: storedConversation.title
                )
                conversation.unreadMessagesCount = storedConversation.unreadMessagesCount
                conversation.messages = storedConversation.messages
                    .sorted(by: { $0.date < $1.date })
                    .map { storedMessage in
                        MessageEvent(
                            id: storedMessage.eventID,
                            senderNick: storedMessage.senderNick,
                            senderUserID: storedMessage.senderUserID,
                            senderIcon: storedMessage.senderIcon,
                            text: storedMessage.text,
                            date: storedMessage.date,
                            isFromCurrentUser: storedMessage.isFromCurrentUser
                        )
                    }
                return conversation
            }

            messageConversations = restoredPrivateConversations + restoredBroadcastConversations
            sortMessageConversations()

            let selectionDescriptor = FetchDescriptor<StoredMessageSelection>(
                predicate: #Predicate<StoredMessageSelection> { $0.connectionKey == key }
            )
            let selection = try modelContext.fetch(selectionDescriptor).first
            selectedMessageConversationID = selection?.selectedConversationID

            if selectedMessageConversationID == nil {
                selectedMessageConversationID = messageConversations.first?.id
            }
        } catch {
            print("[Messages] load failed:", error)
        }
    }

    private func persistMessages() {
        guard let modelContext else { return }
        guard let key = persistenceKey() else { return }

        do {
            let privateDescriptor = FetchDescriptor<StoredPrivateConversation>(
                predicate: #Predicate<StoredPrivateConversation> { $0.connectionKey == key }
            )
            let existingPrivateConversations = try modelContext.fetch(privateDescriptor)
            for conversation in existingPrivateConversations {
                modelContext.delete(conversation)
            }

            let broadcastDescriptor = FetchDescriptor<StoredBroadcastConversation>(
                predicate: #Predicate<StoredBroadcastConversation> { $0.connectionKey == key }
            )
            let existingBroadcastConversations = try modelContext.fetch(broadcastDescriptor)
            for conversation in existingBroadcastConversations {
                modelContext.delete(conversation)
            }

            for conversation in messageConversations where conversation.kind == .direct {
                let storedConversation = StoredPrivateConversation(
                    conversationID: conversation.id,
                    connectionKey: key,
                    title: conversation.title,
                    participantNick: conversation.participantNick,
                    participantUserID: conversation.participantUserID,
                    unreadMessagesCount: conversation.unreadMessagesCount,
                    lastUpdatedAt: conversation.lastMessageDate ?? .distantPast
                )

                storedConversation.messages = conversation.messages.map { message in
                    StoredPrivateMessage(
                        eventID: message.id,
                        senderNick: message.senderNick,
                        senderUserID: message.senderUserID,
                        senderIcon: message.senderIcon,
                        text: message.text,
                        date: message.date,
                        isFromCurrentUser: message.isFromCurrentUser,
                        conversation: storedConversation
                    )
                }

                modelContext.insert(storedConversation)
            }

            for conversation in messageConversations where conversation.kind == .broadcast {
                let storedConversation = StoredBroadcastConversation(
                    conversationID: conversation.id,
                    connectionKey: key,
                    title: conversation.title,
                    unreadMessagesCount: conversation.unreadMessagesCount,
                    lastUpdatedAt: conversation.lastMessageDate ?? .distantPast
                )

                storedConversation.messages = conversation.messages.map { message in
                    StoredBroadcastMessage(
                        eventID: message.id,
                        senderNick: message.senderNick,
                        senderUserID: message.senderUserID,
                        senderIcon: message.senderIcon,
                        text: message.text,
                        date: message.date,
                        isFromCurrentUser: message.isFromCurrentUser,
                        conversation: storedConversation
                    )
                }

                modelContext.insert(storedConversation)
            }

            let selectionDescriptor = FetchDescriptor<StoredMessageSelection>(
                predicate: #Predicate<StoredMessageSelection> { $0.connectionKey == key }
            )
            if let storedSelection = try modelContext.fetch(selectionDescriptor).first {
                storedSelection.selectedConversationID = selectedMessageConversationID
            } else {
                let newSelection = StoredMessageSelection(
                    connectionKey: key,
                    selectedConversationID: selectedMessageConversationID
                )
                modelContext.insert(newSelection)
            }

            try modelContext.save()
        } catch {
            print("[Messages] save failed:", error)
        }
    }

    private func persistenceKey() -> String? {
        if let configuration = connectionController.configuration(for: id) {
            return "\(configuration.hostname.lowercased())|\(configuration.login.lowercased())"
        }

        if let url = connection?.url {
            return "\(url.hostname.lowercased())|\(url.login.lowercased())"
        }

        return nil
    }

    private func onlineUser(withID userID: UInt32) -> User? {
        (chats + private_chats)
            .flatMap(\.users)
            .first(where: { $0.id == userID })
    }

    private func resolvedRecipientUserID(for conversation: MessageConversation) -> UInt32? {
        guard conversation.kind == .direct else { return nil }
        guard let nick = conversation.participantNick else { return nil }

        if let knownID = conversation.participantUserID,
           let user = onlineUser(withID: knownID),
           user.nick == nick {
            return knownID
        }

        if let user = (chats + private_chats)
            .flatMap(\.users)
            .first(where: { $0.nick == nick }) {
            conversation.participantUserID = user.id
            return user.id
        }

        return nil
    }
    
    
    // MARK: -
    
    func send(_ message: P7Message) async throws -> P7Message? {
        isIdle = false
        lastMessageSentAt = .now
        
        return try await connectionController.socketClient.send(message, on: id)
    }
    
    // MARK: -
    
    func getUserInfo(_ userID: UInt32) {
        Task {
            let message = P7Message(withName: "wired.user.get_info", spec: spec!)
            message.addParameter(field: "wired.user.id", value: userID)
            
            showInfosUserID = userID
            
            do {
                if let response = try await send(message) {
                    if response.name == "wired.user.info" {
                        await connectionController.updateUserInfo(from: response, in: self)
                        showInfos.toggle()
                    }
                }
            } catch let error {
                lastError = error
            }
        }
    }
    
    
    // MARK: -
    
    func sendChatMessage( _ chatID: UInt32, _ text: String) async throws -> P7Message? {
        if text.starts(with: "/") {
            if let message = self.chatCommand(chatID, text) {
                return try await self.send(message)
            }
        } else {
            let message = P7Message(withName: "wired.chat.send_say", spec: spec!)
            message.addParameter(field: "wired.chat.id", value: chatID)
            message.addParameter(field: "wired.chat.say", value: text)
            return try await self.send(message)
        }
        
        return nil
    }
    
    
    // MARK: - Chat Messages
    
    func joinChat(_ chatID: UInt32) async throws {
        let message = P7Message(withName: "wired.chat.join_chat", spec: spec!)
        
        message.addParameter(field: "wired.chat.id", value: chatID)
        
        try await self.send(message)
    }
    
    func leaveChat(_ chatID: UInt32) async throws {
        let message = P7Message(withName: "wired.chat.leave_chat", spec: spec!)
        
        message.addParameter(field: "wired.chat.id", value: chatID)
        
        let response = try await self.send(message)

        // Keep server as source of truth: update local state only on explicit success.
        if response?.name == "wired.okay",
           let chat = chat(withID: chatID) {
            if chat.isPrivate {
                removePrivateChat(chatID)
            } else {
                chat.joined = false
                chat.users.removeAll()

                if selectedChatID == chatID {
                    selectedChatID = 1
                }
            }
        }
    }

    @discardableResult
    func createPrivateChat() async throws -> UInt32 {
        let message = P7Message(withName: "wired.chat.create_chat", spec: spec!)
        guard let response = try await self.send(message) else {
            throw WiredError(withTitle: "Private Chat", message: "No response from server.")
        }

        if response.name == "wired.error" {
            throw WiredError(message: response)
        }

        guard response.name == "wired.chat.chat_created",
              let chatID = response.uint32(forField: "wired.chat.id") else {
            throw WiredError(withTitle: "Private Chat", message: "Invalid server response.")
        }

        if chat(withID: chatID) == nil {
            appendPrivateChat(Chat(id: chatID, name: "Private Chat", isPrivate: true))
        }

        selectedChatID = chatID

        try await joinChat(chatID)
        _ = await waitForChatJoin(chatID, timeout: 2.0)
        return chatID
    }

    func createPrivateChat(inviting userID: UInt32) async throws {
        let chatID = try await createPrivateChat()
        try await inviteUserToPrivateChat(userID: userID, chatID: chatID)
    }

    func inviteUserToPrivateChat(userID: UInt32, chatID: UInt32) async throws {
        let message = P7Message(withName: "wired.chat.invite_user", spec: spec!)
        message.addParameter(field: "wired.chat.id", value: chatID)
        message.addParameter(field: "wired.user.id", value: userID)

        if let response = try await send(message), response.name == "wired.error" {
            throw WiredError(message: response)
        }
    }

    func acceptPendingChatInvitation() {
        guard let invitation = pendingChatInvitation else { return }

        Task {
            do {
                try await joinChat(invitation.chatID)
            } catch {
                lastError = error
            }
        }

        pendingChatInvitation = nil
        selectedChatID = invitation.chatID
    }

    func declinePendingChatInvitation() {
        guard let invitation = pendingChatInvitation else { return }

        Task {
            do {
                let message = P7Message(withName: "wired.chat.decline_invitation", spec: spec!)
                message.addParameter(field: "wired.chat.id", value: invitation.chatID)
                message.addParameter(field: "wired.user.id", value: invitation.inviterUserID)

                if let response = try await send(message), response.name == "wired.error" {
                    lastError = WiredError(message: response)
                }
            } catch {
                lastError = error
            }
        }

        pendingChatInvitation = nil
    }

    func refreshPrivateChatName(_ chat: Chat) {
        guard chat.isPrivate else { return }

        let others = chat.users
            .filter { $0.id != userID }
            .map { $0.nick }
            .sorted()

        chat.name = others.isEmpty ? "Private Chat" : others.joined(separator: ", ")
    }

    private func waitForChatJoin(_ chatID: UInt32, timeout: TimeInterval) async -> Bool {
        let end = Date().addingTimeInterval(timeout)

        while Date() < end {
            if let chat = chat(withID: chatID), chat.joined {
                return true
            }

            try? await Task.sleep(for: .milliseconds(100))
        }

        return false
    }
    
    func deletePublicChat(_ chatID: UInt32) async throws {
        let message = P7Message(withName: "wired.chat.delete_public_chat", spec: spec!)
        
        message.addParameter(field: "wired.chat.id", value: chatID)
        
        try await self.send(message)
    }
    
    
    // MARK: - User Status Messages
    
    func setNickMessage(_ nick:String) -> P7Message? {
        let message = P7Message(withName: "wired.user.set_nick", spec: spec!)
        message.addParameter(field: "wired.user.nick", value: nick)

        return message
    }
    
    func setStatusMessage(_ status:String) -> P7Message? {
        let message = P7Message(withName: "wired.user.set_status", spec: spec!)
        message.addParameter(field: "wired.user.status", value: status)

        return message
    }
    
    func setIconMessage(_ icon:Data) -> P7Message? {
        let message = P7Message(withName: "wired.user.set_icon", spec: spec!)
        
        message.addParameter(field: "wired.user.icon", value: icon)
        
        return message
    }
    
    
    // MARK: -
    
    private func chatCommand(_ chatID: UInt32, _ command: String) -> P7Message? {
        let comps = command.split(separator: " ")
                
        if comps[0] == "/me" {
            let value = command.deletingPrefix(comps[0]+" ")
                        
            if value.count == 0 || value == comps[0] {
                return nil
            }

            let message = P7Message(withName: "wired.chat.send_me", spec: spec!)

            message.addParameter(field: "wired.chat.id", value: chatID)
            message.addParameter(field: "wired.chat.me", value: value)
            
            return message
        }
        
        else if comps[0] == "/nick" {
            let value = command.deletingPrefix(comps[0]+" ")
            
            if value.count == 0 || value == comps[0] {
                return nil
            }
                        
            return self.setNickMessage(value)
        }
            
        else if comps[0] == "/status" {
            let value = command.deletingPrefix(comps[0]+" ")
            
            if value.count == 0 || value == comps[0] {
                return nil
            }
                        
            return self.setStatusMessage(value)
        }
        
        else if comps[0] == "/topic" {
            let value = command.deletingPrefix(comps[0]+" ")
            
            if value.count == 0 || value == comps[0] {
                return nil
            }

            let message = P7Message(withName: "wired.chat.set_topic", spec: spec!)

            message.addParameter(field: "wired.chat.id", value: chatID)
            message.addParameter(field: "wired.chat.topic.topic", value: value)
            
            return message
        }
            
        else if comps[0] == "/help" {
            var string = "Chat commands:\n\n"
            string += "/me\t\tSend a third-person message\n"
            string += "/nick\tUpdate your user nick\n"
            string += "/status\tUpdate your user status\n"
            string += "/topic\tSet the chat topic\n"
            string += "/help\tShow this help message\n"
            
            let message = P7Message(withName: "wired.chat.send_say", spec: spec!)

            message.addParameter(field: "wired.chat.id", value: chatID)
            message.addParameter(field: "wired.chat.say", value: string)
            
            return message
        }
        
        return nil
    }
    
    // MARK: - Board Messages

    func getBoards() async throws {
        let m = P7Message(withName: "wired.board.get_boards", spec: spec!)
        try await send(m)
    }

    func subscribeBoards() async throws {
        let m = P7Message(withName: "wired.board.subscribe_boards", spec: spec!)
        try await send(m)
    }

    func getThreads(forBoard board: Board) async throws {
        board.threadsLoaded = false
        board.threads.removeAll()
        let m = P7Message(withName: "wired.board.get_threads", spec: spec!)
        m.addParameter(field: "wired.board.board", value: board.path)
        try await send(m)
        board.threadsLoaded = true
    }

    func getPosts(forThread thread: BoardThread) async throws {
        thread.postsLoaded = false
        thread.posts.removeAll()
        let m = P7Message(withName: "wired.board.get_thread", spec: spec!)
        m.addParameter(field: "wired.board.thread", value: thread.uuid)
        try await send(m)
    }

    func addThread(toBoard board: Board, subject: String, text: String) async throws {
        let m = P7Message(withName: "wired.board.add_thread", spec: spec!)
        m.addParameter(field: "wired.board.board",   value: board.path)
        m.addParameter(field: "wired.board.subject", value: subject)
        m.addParameter(field: "wired.board.text",    value: text)
        if let response = try await send(m), response.name == "wired.error" {
            throw WiredError(message: response)
        }
    }

    func addPost(toThread thread: BoardThread, text: String) async throws {
        let m = P7Message(withName: "wired.board.add_post", spec: spec!)
        m.addParameter(field: "wired.board.thread",  value: thread.uuid)
        m.addParameter(field: "wired.board.subject", value: thread.subject)
        m.addParameter(field: "wired.board.text",    value: text)
        if let response = try await send(m), response.name == "wired.error" {
            throw WiredError(message: response)
        }

        // Optimistic append: avoids full reload when the thread is already loaded.
        if thread.postsLoaded {
            let me = onlineUser(withID: userID)
            let localUUID = "local-\(UUID().uuidString.lowercased())"
            let post = BoardPost(
                uuid: localUUID,
                threadUUID: thread.uuid,
                text: text,
                nick: me?.nick ?? (connection?.nick ?? "Me"),
                postDate: Date(),
                icon: me?.icon,
                isOwn: true
            )
            post.isUnread = false
            thread.posts.append(post)
            pendingLocalPostUUIDByThread[thread.uuid] = localUUID
        }
    }

    func pendingLocalPostUUID(forThread threadUUID: String) -> String? {
        pendingLocalPostUUIDByThread[threadUUID]
    }

    func clearPendingLocalPostUUID(forThread threadUUID: String) {
        pendingLocalPostUUIDByThread.removeValue(forKey: threadUUID)
    }

    func addBoard(
        path: String,
        owner: String,
        ownerRead: Bool,
        ownerWrite: Bool,
        group: String,
        groupRead: Bool,
        groupWrite: Bool,
        everyoneRead: Bool,
        everyoneWrite: Bool
    ) async throws {
        let m = P7Message(withName: "wired.board.add_board", spec: spec!)
        m.addParameter(field: "wired.board.board", value: path)
        m.addParameter(field: "wired.board.owner", value: owner)
        m.addParameter(field: "wired.board.owner.read", value: ownerRead)
        m.addParameter(field: "wired.board.owner.write", value: ownerWrite)
        m.addParameter(field: "wired.board.group", value: group)
        m.addParameter(field: "wired.board.group.read", value: groupRead)
        m.addParameter(field: "wired.board.group.write", value: groupWrite)
        m.addParameter(field: "wired.board.everyone.read", value: everyoneRead)
        m.addParameter(field: "wired.board.everyone.write", value: everyoneWrite)

        guard let response = try await send(m) else {
            throw WiredError(withTitle: "Board", message: "No response from server.")
        }

        if response.name == "wired.error" {
            throw WiredError(message: response)
        }
    }

    func listAccountUserNames() async throws -> [String] {
        guard let connection = connection as? AsyncConnection else {
            throw WiredError(withTitle: "Accounts", message: "Not connected.")
        }

        let message = P7Message(withName: "wired.account.list_users", spec: spec!)
        var values: [String] = []

        for try await response in try connection.sendAndWaitMany(message) {
            if response.name == "wired.error" {
                throw WiredError(message: response)
            }

            if response.name == "wired.account.user_list",
               let name = response.string(forField: "wired.account.name"),
               !name.isEmpty {
                values.append(name)
            }
        }

        return Array(Set(values)).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    func listAccountGroupNames() async throws -> [String] {
        guard let connection = connection as? AsyncConnection else {
            throw WiredError(withTitle: "Accounts", message: "Not connected.")
        }

        let message = P7Message(withName: "wired.account.list_groups", spec: spec!)
        var values: [String] = []

        for try await response in try connection.sendAndWaitMany(message) {
            if response.name == "wired.error" {
                throw WiredError(message: response)
            }

            if response.name == "wired.account.group_list",
               let name = response.string(forField: "wired.account.name"),
               !name.isEmpty {
                values.append(name)
            }
        }

        return Array(Set(values)).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    func getBoardInfo(path: String) async throws {
        let m = P7Message(withName: "wired.board.get_board_info", spec: spec!)
        m.addParameter(field: "wired.board.board", value: path)

        guard let response = try await send(m) else {
            throw WiredError(withTitle: "Board", message: "No response from server.")
        }

        if response.name == "wired.error" {
            throw WiredError(message: response)
        }
    }

    func setBoardInfo(
        path: String,
        owner: String,
        ownerRead: Bool,
        ownerWrite: Bool,
        group: String,
        groupRead: Bool,
        groupWrite: Bool,
        everyoneRead: Bool,
        everyoneWrite: Bool
    ) async throws {
        let m = P7Message(withName: "wired.board.set_board_info", spec: spec!)
        m.addParameter(field: "wired.board.board", value: path)
        m.addParameter(field: "wired.board.owner", value: owner)
        m.addParameter(field: "wired.board.owner.read", value: ownerRead)
        m.addParameter(field: "wired.board.owner.write", value: ownerWrite)
        m.addParameter(field: "wired.board.group", value: group)
        m.addParameter(field: "wired.board.group.read", value: groupRead)
        m.addParameter(field: "wired.board.group.write", value: groupWrite)
        m.addParameter(field: "wired.board.everyone.read", value: everyoneRead)
        m.addParameter(field: "wired.board.everyone.write", value: everyoneWrite)

        guard let response = try await send(m) else {
            throw WiredError(withTitle: "Board", message: "No response from server.")
        }

        if response.name == "wired.error" {
            throw WiredError(message: response)
        }
    }

    func deleteThread(uuid: String) async throws {
        let m = P7Message(withName: "wired.board.delete_thread", spec: spec!)
        m.addParameter(field: "wired.board.thread", value: uuid)
        if let response = try await send(m), response.name == "wired.error" {
            throw WiredError(message: response)
        }
    }

    func deletePost(uuid: String) async throws {
        let m = P7Message(withName: "wired.board.delete_post", spec: spec!)
        m.addParameter(field: "wired.board.post", value: uuid)
        if let response = try await send(m), response.name == "wired.error" {
            throw WiredError(message: response)
        }
    }

    func deleteBoard(path: String) async throws {
        let m = P7Message(withName: "wired.board.delete_board", spec: spec!)
        m.addParameter(field: "wired.board.board", value: path)
        if let response = try await send(m), response.name == "wired.error" {
            throw WiredError(message: response)
        }
    }

    func renameBoard(path: String, newPath: String) async throws {
        let m = P7Message(withName: "wired.board.rename_board", spec: spec!)
        m.addParameter(field: "wired.board.board", value: path)
        m.addParameter(field: "wired.board.new_board", value: newPath)
        if let response = try await send(m), response.name == "wired.error" {
            throw WiredError(message: response)
        }
    }

    func moveBoard(path: String, newPath: String) async throws {
        let m = P7Message(withName: "wired.board.move_board", spec: spec!)
        m.addParameter(field: "wired.board.board", value: path)
        m.addParameter(field: "wired.board.new_board", value: newPath)
        if let response = try await send(m), response.name == "wired.error" {
            throw WiredError(message: response)
        }
    }

    func editThread(uuid: String, subject: String, text: String) async throws {
        let m = P7Message(withName: "wired.board.edit_thread", spec: spec!)
        m.addParameter(field: "wired.board.thread", value: uuid)
        m.addParameter(field: "wired.board.subject", value: subject)
        m.addParameter(field: "wired.board.text", value: text)
        if let response = try await send(m), response.name == "wired.error" {
            throw WiredError(message: response)
        }
    }

    func moveThread(uuid: String, newBoardPath: String) async throws {
        let m = P7Message(withName: "wired.board.move_thread", spec: spec!)
        m.addParameter(field: "wired.board.thread", value: uuid)
        m.addParameter(field: "wired.board.new_board", value: newBoardPath)
        if let response = try await send(m), response.name == "wired.error" {
            throw WiredError(message: response)
        }
    }

    func editPost(uuid: String, subject: String, text: String) async throws {
        let m = P7Message(withName: "wired.board.edit_post", spec: spec!)
        m.addParameter(field: "wired.board.post", value: uuid)
        m.addParameter(field: "wired.board.subject", value: subject)
        m.addParameter(field: "wired.board.text", value: text)
        if let response = try await send(m), response.name == "wired.error" {
            throw WiredError(message: response)
        }
    }

    // MARK: - Unreads
    
    public func resetUnreads(_ chat: Chat) {
        chat.unreadMessagesCount = 0
        connectionController.updateNotificationsBadge()
    }
    
    // MARK: -
    
    func hasPrivilege(_ privilege: String) -> Bool {
        if let p = privileges[privilege] as? Bool {
            return p
        }
        return false
    }
}
