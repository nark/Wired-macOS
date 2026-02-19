//
//  ConnectionRuntime.swift
//  Wired-macOS
//
//  Created by Rafaël Warnault on 19/12/2025.
//  Copyright © 2025 Read-Write. All rights reserved.
//

import SwiftUI
import WiredSwift

struct ChatInvitation: Equatable {
    let chatID: UInt32
    let inviterUserID: UInt32
    let inviterNick: String?
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
    
    var serverInfo: P7Message? = nil
    var chats: [Chat] = []
    var private_chats: [Chat] = []
    var pendingChatInvitation: ChatInvitation? = nil
    
    var showInfos: Bool = false
    var showInfosUserID: UInt32 = 0
        
    private let defaults = UserDefaults.standard

    var substituteEmoji: Bool {
        defaults.bool(forKey: "SubstituteEmoji")
    }
    
    var totalUnreadMessages: Int {
        totalUnreadChatMessages
    }
    
    var totalUnreadChatMessages: Int {
        (chats + private_chats).reduce(0) { $0 + $1.unreadMessagesCount }
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
    

    // MARK: - Connection State

    func connect() {
        lastError = nil
        privileges = [:]
        userID = 0
        status = .connecting
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
