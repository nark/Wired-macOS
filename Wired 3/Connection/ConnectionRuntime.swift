//
//  ConnectionRuntime.swift
//  Wired-macOS
//
//  Created by Rafaël Warnault on 19/12/2025.
//  Copyright © 2025 Read-Write. All rights reserved.
//

import SwiftUI
import WiredSwift

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
        chats.reduce(0) { $0 + $1.unreadMessagesCount }
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
        status = .connecting
    }

    func connected(_ connection: Connection) {
        self.connection = connection
        lastError = nil
        status = .connected
    }

    func disconnect(error: Error? = nil) {
        joined = false
        status = .disconnected
        
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
    }

    func appendChat(_ chat: Chat) {
        chats.append(chat)
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
        
        try await self.send(message)
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
