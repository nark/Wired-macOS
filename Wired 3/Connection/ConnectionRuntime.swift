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
    
    var showInfos: Bool = false
    var showInfosUserID: UInt32 = 0
        
    private let defaults = UserDefaults.standard

    var substituteEmoji: Bool {
        defaults.bool(forKey: "SubstituteEmoji")
    }
    
    var totalUnreadMessages: Int {
        totalUnreadChatMessages + totalUnreadPrivateMessages
    }
    
    var totalUnreadChatMessages: Int {
        (chats + private_chats).reduce(0) { $0 + $1.unreadMessagesCount }
    }

    var totalUnreadPrivateMessages: Int {
        messageConversations.reduce(0) { $0 + $1.unreadMessagesCount }
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
        privileges = [:]
        userID = 0
        status = .connecting
        loadPersistedMessagesIfNeeded()
    }

    func connected(_ connection: Connection) {
        self.connection = connection
        lastError = nil
        status = .connected
    }

    func disconnect(error: Error? = nil) {
        joined = false
        privileges = [:]
        userID = 0
        status = .disconnected
        pendingChatInvitation = nil
        
        if let error {
            lastError = error
        }
        
        resetChats()
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
