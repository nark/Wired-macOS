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
import UniformTypeIdentifiers
import CryptoKit

struct ChatInvitation: Equatable {
    let chatID: UInt32
    let inviterUserID: UInt32
    let inviterNick: String?
}

private extension String {
    func resolvingDraftAttachmentReferences(using mapping: [String: String]) -> String {
        var resolved = self

        for (draftID, attachmentID) in mapping {
            resolved = resolved.replacingOccurrences(
                of: "attachment://draft/\(draftID)",
                with: "attachment://\(attachmentID.lowercased())"
            )
        }

        let unresolvedPattern = #"!?\[[^\]]*\]\(attachment://draft/[0-9a-fA-F\-]+\)"#
        if let regex = try? NSRegularExpression(pattern: unresolvedPattern) {
            let range = NSRange(resolved.startIndex..<resolved.endIndex, in: resolved)
            resolved = regex.stringByReplacingMatches(in: resolved, options: [], range: range, withTemplate: "")
        }

        return resolved
    }

    func removingUnboundAttachmentReferences(allowedAttachmentIDs: Set<String>) -> String {
        let pattern = #"!?\[[^\]]*\]\(attachment://([0-9a-fA-F\-]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return self }

        let source = self
        let matches = regex.matches(in: source, options: [], range: NSRange(source.startIndex..<source.endIndex, in: source)).reversed()
        var result = source

        for match in matches {
            guard match.numberOfRanges >= 2,
                  let fullRange = Range(match.range(at: 0), in: result),
                  let idRange = Range(match.range(at: 1), in: source) else {
                continue
            }

            let attachmentID = String(source[idRange]).lowercased()
            guard !allowedAttachmentIDs.contains(attachmentID) else { continue }
            result.removeSubrange(fullRange)
        }

        return result
    }
}

struct PendingBoardPostScrollTarget: Equatable {
    let threadUUID: String
    let postUUID: String
}

struct BanListEntry: Identifiable, Hashable {
    let ipPattern: String
    let expirationDate: Date?

    var id: String {
        let timestamp = expirationDate?.timeIntervalSince1970 ?? -1
        return "\(ipPattern)|\(timestamp)"
    }
}

struct ModerationNotice: Identifiable, Equatable {
    let id: UUID
    let title: String
    let message: String

    init(id: UUID = UUID(), title: String, message: String) {
        self.id = id
        self.title = title
        self.message = message
    }
}

enum MessageConversationKind {
    case direct
    case broadcast
}

// MARK: - Chat Commands

enum ChatCommand: String, CaseIterable {
    case me        = "/me"
    case nick      = "/nick"
    case status    = "/status"
    case topic     = "/topic"
    case broadcast = "/broadcast"
    case stats     = "/stats"
    case clear     = "/clear"
    case afk       = "/afk"
    case help      = "/help"

    /// Short argument placeholder shown in autocomplete (empty if no argument)
    var hint: String {
        switch self {
        case .me:        return "<action>"
        case .nick:      return "<new_nick>"
        case .status:    return "<new_status>"
        case .topic:     return "<new_topic>"
        case .broadcast: return "<message>"
        case .afk:       return ""
        case .stats:     return ""
        case .clear:     return ""
        case .help:      return ""
        }
    }

    /// One-line description used in /help and autocomplete
    var usage: String {
        switch self {
        case .me:        return "Send a third-person action message"
        case .nick:      return "Change your display name"
        case .status:    return "Update your status message"
        case .topic:     return "Set the chat topic"
        case .broadcast: return "Send a broadcast message to all users"
        case .afk:       return "Set away-from-keyboard status"
        case .stats:     return "Show server statistics"
        case .clear:     return "Clear the chat view"
        case .help:      return "Show available commands"
        }
    }
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
    let attachments: [ChatAttachmentDescriptor]

    @ObservationIgnored private var imageURLCacheResolved = false
    @ObservationIgnored private var cachedImageURL: URL?

    var cachedPrimaryHTTPImageURL: URL? {
        if !imageURLCacheResolved {
            imageURLCacheResolved = true
            cachedImageURL = text.detectedHTTPImageURLs().first
        }
        return cachedImageURL
    }

    init(
        id: UUID = UUID(),
        senderNick: String,
        senderUserID: UInt32?,
        senderIcon: Data?,
        text: String,
        date: Date = Date(),
        isFromCurrentUser: Bool,
        attachments: [ChatAttachmentDescriptor] = []
    ) {
        self.id = id
        self.senderNick = senderNick
        self.senderUserID = senderUserID
        self.senderIcon = senderIcon
        self.text = text
        self.date = date
        self.isFromCurrentUser = isFromCurrentUser
        self.attachments = attachments
    }
}

@Observable
@MainActor
final class MessageConversation: Identifiable {
    private struct SearchCacheEntry {
        let query: String
        let messageCount: Int
        let lastMessageID: UUID?
        let title: String
        let participantNick: String?
        let matches: Bool
        let matchingMessages: [MessageEvent]
        let previewText: String?
    }

    let id: UUID
    let kind: MessageConversationKind
    var title: String
    var participantNick: String?
    var participantUserID: UInt32?
    var participantLogin: String?
    var messages: [MessageEvent] = []
    var unreadMessagesCount: Int = 0
    @ObservationIgnored private var searchCache: SearchCacheEntry?

    var lastMessageDate: Date? {
        messages.last?.date
    }

    init(
        id: UUID = UUID(),
        kind: MessageConversationKind,
        title: String,
        participantNick: String? = nil,
        participantUserID: UInt32? = nil,
        participantLogin: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.participantNick = participantNick
        self.participantUserID = participantUserID
        self.participantLogin = participantLogin
    }
}

extension MessageEvent {
    func matchesSearch(_ rawQuery: String) -> Bool {
        let query = rawQuery.trimmedMessageSearchQuery
        guard !query.isEmpty else { return true }

        return senderNick.localizedStandardContains(query)
            || text.localizedStandardContains(query)
    }
}

extension MessageConversation {
    func matchesSearch(_ rawQuery: String) -> Bool {
        searchCacheEntry(for: rawQuery).matches
    }

    func filteredMessages(matching rawQuery: String) -> [MessageEvent] {
        searchCacheEntry(for: rawQuery).matchingMessages
    }

    func previewText(matching rawQuery: String) -> String? {
        searchCacheEntry(for: rawQuery).previewText
    }

    private func matchesMetadata(_ query: String) -> Bool {
        if title.localizedStandardContains(query) {
            return true
        }

        if let participantNick, participantNick.localizedStandardContains(query) {
            return true
        }

        return false
    }

    private func searchCacheEntry(for rawQuery: String) -> SearchCacheEntry {
        let query = rawQuery.trimmedMessageSearchQuery
        let lastMessageID = messages.last?.id

        if let searchCache,
           searchCache.query == query,
           searchCache.messageCount == messages.count,
           searchCache.lastMessageID == lastMessageID,
           searchCache.title == title,
           searchCache.participantNick == participantNick {
            return searchCache
        }

        let entry: SearchCacheEntry
        if query.isEmpty {
            entry = SearchCacheEntry(
                query: query,
                messageCount: messages.count,
                lastMessageID: lastMessageID,
                title: title,
                participantNick: participantNick,
                matches: true,
                matchingMessages: messages,
                previewText: messages.last?.text
            )
        } else {
            let matchingMessages = messages.filter { $0.matchesSearch(query) }
            entry = SearchCacheEntry(
                query: query,
                messageCount: messages.count,
                lastMessageID: lastMessageID,
                title: title,
                participantNick: participantNick,
                matches: matchesMetadata(query) || !matchingMessages.isEmpty,
                matchingMessages: matchingMessages,
                previewText: matchingMessages.last?.text ?? messages.last?.text
            )
        }

        searchCache = entry
        return entry
    }
}

private extension String {
    var trimmedMessageSearchQuery: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@Observable
@MainActor
final class ConnectionRuntime: Identifiable {
    let id: UUID
    let connectionController: ConnectionController

    var connection: Connection?

    var selectedTab: MainTab = .chats
    var selectedChatID: UInt32? = 1
    var chatDrafts: [UInt32: String] = [:]
    var chatDraftAttachments: [UInt32: [ChatDraftAttachment]] = [:]
    var messageDrafts: [UUID: String] = [:]
    var messageDraftAttachments: [UUID: [ChatDraftAttachment]] = [:]
    var userID: UInt32 = 0
    var privileges: [String: Any] = [:]

    var status: Status = .disconnected
    var joined = false
    var lastError: Error?
    var moderationNotice: ModerationNotice?
    var hasConnectionIssue: Bool = false
    var isAutoReconnectScheduled: Bool = false
    var autoReconnectAttempt: Int = 0
    var autoReconnectInterval: TimeInterval = 0
    var autoReconnectNextAttemptAt: Date?

    private let incomingTypingTimeout: TimeInterval = 6.5
    @ObservationIgnored
    private var typingCleanupTask: Task<Void, Never>?
    @ObservationIgnored
    private var activeOutgoingTypingChatIDs: Set<UInt32> = []
    private var didLoadPersistedMessages: Bool = false
    private var modelContext: ModelContext?

    var serverInfo: ServerInfo?
    var chats: [Chat] = []
    var private_chats: [Chat] = []

    var pendingChatInvitation: ChatInvitation?
    var pendingTopicSheet: Bool = false
    var pendingBroadcastConversation: Bool = false
    var selectedMessageConversationID: UUID?
    var messageConversations: [MessageConversation] = []
    var offlineUsers: [OfflineUser] = []

    // Boards
    var boards: [Board] = []
    @ObservationIgnored
    var boardsByPath: [String: Board] = [:]
    @ObservationIgnored
    private var pendingLocalPostUUIDByThread: [String: String] = [:]
    /// Reaction emojis that arrived while a thread's reactions weren't loaded yet.
    /// Outer key: threadUUID. Inner key: postUUID or "body" for the thread body.
    /// Applied as shake animations when `getReactions` completes for the matching post.
    @ObservationIgnored
    private var pendingReactionAnimations: [String: [String: Set<String>]] = [:]
    @ObservationIgnored
    private(set) var boardReadIDs: Set<String> = []
    var allBoardThreadsLoaded: Bool = false
    var boardsLoaded: Bool = false
    var selectedBoardPath: String?
    var selectedThreadUUID: String?
    var selectedSmartBoardID: String?
    var boardSearchResults: [BoardSearchResult] = []
    var isSearchingBoards: Bool = false
    var boardNetworkActivityCount: Int = 0
    var pendingBoardPostScrollTarget: PendingBoardPostScrollTarget?

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

    var isPerformingBoardNetworkActivity: Bool {
        boardNetworkActivityCount > 0
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
        moderationNotice = nil
        hasConnectionIssue = false
        privileges = [:]
        userID = 0
        serverInfo = nil
        status = .connecting
        resetAutoReconnectState()
        loadPersistedBoardReadIDs()
        loadPersistedMessagesIfNeeded()
    }

    func connected(_ connection: Connection) {
        self.connection = connection
        self.serverInfo = connection.serverInfo
        lastError = nil
        hasConnectionIssue = false
        status = .connected
        resetAutoReconnectState()
        startTypingCleanupTimer()
    }

    func disconnect(error: Error? = nil) {
        let previousStatus = status
        sendOutgoingTypingStopSignals()
        stopTypingCleanupTimer()
        clearAllTypingState()
        joined = false
        privileges = [:]
        userID = 0
        serverInfo = nil
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
        offlineUsers = []
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

    // MARK: - Typing Indicator

    private func startTypingCleanupTimer() {
        stopTypingCleanupTimer()

        typingCleanupTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self.pruneExpiredTypingIndicators()
            }
        }
    }

    private func stopTypingCleanupTimer() {
        typingCleanupTask?.cancel()
        typingCleanupTask = nil
    }

    private func pruneExpiredTypingIndicators(referenceDate: Date = .now) {
        for chat in chats + private_chats {
            chat.removeExpiredTypingUsers(referenceDate: referenceDate)
        }
    }

    private func clearAllTypingState() {
        activeOutgoingTypingChatIDs.removeAll()

        for chat in chats + private_chats {
            chat.clearAllTyping()
        }
    }

    private func sendOutgoingTypingStopSignals() {
        guard !activeOutgoingTypingChatIDs.isEmpty else { return }

        let chatIDs = activeOutgoingTypingChatIDs
        activeOutgoingTypingChatIDs.removeAll()

        guard connection != nil else { return }

        for chatID in chatIDs {
            let message = P7Message(withName: "wired.chat.send_typing", spec: spec)
            message.addParameter(field: "wired.chat.id", value: chatID)
            message.addParameter(field: "wired.chat.typing", value: false)

            Task {
                _ = try? await connectionController.socketClient.send(message, on: id)
            }
        }
    }

    func setChatTyping(chatID: UInt32, isTyping: Bool) async {
        guard chat(withID: chatID) != nil else {
            activeOutgoingTypingChatIDs.remove(chatID)
            return
        }

        if !isTyping && !activeOutgoingTypingChatIDs.contains(chatID) {
            return
        }

        if isTyping {
            activeOutgoingTypingChatIDs.insert(chatID)
        } else {
            activeOutgoingTypingChatIDs.remove(chatID)
        }

        guard connection != nil else { return }

        let message = P7Message(withName: "wired.chat.send_typing", spec: spec)
        message.addParameter(field: "wired.chat.id", value: chatID)
        message.addParameter(field: "wired.chat.typing", value: isTyping)

        _ = try? await send(message)
    }

    func applyIncomingChatTyping(chatID: UInt32, userID: UInt32, isTyping: Bool) {
        guard let chat = chat(withID: chatID), userID != self.userID else { return }

        if isTyping {
            chat.setTyping(userID: userID, expiresAt: Date().addingTimeInterval(incomingTypingTimeout))
        } else {
            chat.clearTyping(userID: userID)
        }
    }

    func clearIncomingChatTyping(chatID: UInt32, userID: UInt32) {
        guard let chat = chat(withID: chatID) else { return }
        chat.clearTyping(userID: userID)
    }

    // MARK: - Chat Models

    func resetChats() {
        clearAllTypingState()
        chats = []
        private_chats = []
    }

    func resetMessages() {
        selectedMessageConversationID = nil
        messageConversations = []
        offlineUsers = []
        persistMessages()
    }

    // MARK: - Board Models

    func resetBoards() {
        boards = []
        boardsByPath = [:]
        allBoardThreadsLoaded = false
        boardsLoaded = false
        selectedBoardPath = nil
        selectedThreadUUID = nil
        selectedSmartBoardID = nil
        boardSearchResults = []
        isSearchingBoards = false
        pendingBoardPostScrollTarget = nil
        connectionController.updateNotificationsBadge()
    }

    func appendBoard(_ board: Board) {
        board.threadsLoaded = allBoardThreadsLoaded
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
                await self.reloadBoardsAndThreads()
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

    func reloadBoardsAndThreads() async {
        resetBoards()
        try? await getBoards()
        await bootstrapBoardThreads()
    }

    private func withBoardNetworkActivity<T>(_ operation: () async throws -> T) async rethrows -> T {
        boardNetworkActivityCount += 1
        defer {
            boardNetworkActivityCount = max(0, boardNetworkActivityCount - 1)
        }
        return try await operation()
    }

    func bootstrapBoardThreads() async {
        do {
            try await getAllThreads()
        } catch {
            allBoardThreadsLoaded = false

            let boardsToLoad = boardsByPath.values.sorted { $0.path < $1.path }
            var loadedAllBoards = true

            for board in boardsToLoad {
                do {
                    try await getThreads(forBoard: board)
                } catch {
                    loadedAllBoards = false
                }
            }

            allBoardThreadsLoaded = loadedAllBoards
        }
    }

    private func persistedBoardReadIDsKey() -> String? {
        guard let key = persistenceKey() else { return nil }
        return "BoardReadIDs|\(key)"
    }

    private func loadPersistedBoardReadIDs() {
        guard let key = persistedBoardReadIDsKey() else { return }
        guard let data = defaults.data(forKey: key) else {
            boardReadIDs = []
            return
        }

        do {
            let decoded = try JSONDecoder().decode([String].self, from: data)
            boardReadIDs = Set(decoded)
        } catch {
            boardReadIDs = Set(defaults.stringArray(forKey: key) ?? [])
        }

        refreshAllBoardUnreadStates()
    }

    private func persistBoardReadIDs() {
        guard let key = persistedBoardReadIDsKey() else { return }
        let encoded = Array(boardReadIDs).sorted()

        do {
            defaults.set(try JSONEncoder().encode(encoded), forKey: key)
        } catch {
            defaults.set(encoded, forKey: key)
        }
    }

    private func unreadMarker(for thread: BoardThread) -> String {
        thread.lastReplyUUID ?? thread.uuid
    }

    private func isThreadUnread(_ thread: BoardThread) -> Bool {
        !boardReadIDs.contains(unreadMarker(for: thread))
    }

    private func isPostUnread(_ post: BoardPost, in thread: BoardThread) -> Bool {
        if post.isThreadBody {
            guard thread.lastReplyUUID == nil else { return false }
            return !boardReadIDs.contains(thread.uuid)
        }

        return !boardReadIDs.contains(post.uuid)
    }

    func refreshThreadUnreadState(for thread: BoardThread, updateBadge: Bool = true) {
        thread.isUnreadThread = isThreadUnread(thread)

        var unreadCount = 0
        for post in thread.posts {
            let unread = isPostUnread(post, in: thread)
            post.isUnread = unread
            if unread {
                unreadCount += 1
            }
        }

        thread.unreadPostsCount = max(unreadCount, thread.isUnreadThread ? 1 : 0)

        if updateBadge {
            connectionController.updateNotificationsBadge()
        }
    }

    func refreshAllBoardUnreadStates() {
        for board in boardsByPath.values {
            for thread in board.threads {
                refreshThreadUnreadState(for: thread, updateBadge: false)
            }
        }
        connectionController.updateNotificationsBadge()
    }

    private func markThreadAsRead(_ thread: BoardThread, persist: Bool, updateBadge: Bool) {
        boardReadIDs.insert(thread.uuid)
        if let latestReplyUUID = thread.lastReplyUUID {
            boardReadIDs.insert(latestReplyUUID)
        }
        for post in thread.posts where !post.isThreadBody {
            boardReadIDs.insert(post.uuid)
        }
        thread.unreadReactionCount = 0
        if persist {
            persistBoardReadIDs()
        }
        refreshThreadUnreadState(for: thread, updateBadge: updateBadge)
    }

    func markThreadAsRead(_ thread: BoardThread) {
        markThreadAsRead(thread, persist: true, updateBadge: true)
    }

    func markThreadAsRead(boardPath: String, threadUUID: String) {
        guard let thread = thread(boardPath: boardPath, uuid: threadUUID) else { return }
        markThreadAsRead(thread)
    }

    private func markThreadAsUnread(_ thread: BoardThread, persist: Bool, updateBadge: Bool) {
        if let latestReplyUUID = thread.lastReplyUUID {
            boardReadIDs.remove(latestReplyUUID)
        } else {
            boardReadIDs.remove(thread.uuid)
        }
        if persist {
            persistBoardReadIDs()
        }
        refreshThreadUnreadState(for: thread, updateBadge: updateBadge)
    }

    func markThreadAsUnread(_ thread: BoardThread) {
        markThreadAsUnread(thread, persist: true, updateBadge: true)
    }

    func markThreadsAsRead(_ threads: [BoardThread]) {
        let uniqueThreads = Array(Dictionary(grouping: threads, by: \.uuid).values.compactMap(\.first))
        guard !uniqueThreads.isEmpty else { return }

        for thread in uniqueThreads {
            markThreadAsRead(thread, persist: false, updateBadge: false)
        }

        persistBoardReadIDs()
        connectionController.updateNotificationsBadge()
    }

    func markThreadsAsUnread(_ threads: [BoardThread]) {
        let uniqueThreads = Array(Dictionary(grouping: threads, by: \.uuid).values.compactMap(\.first))
        guard !uniqueThreads.isEmpty else { return }

        for thread in uniqueThreads {
            markThreadAsUnread(thread, persist: false, updateBadge: false)
        }

        persistBoardReadIDs()
        connectionController.updateNotificationsBadge()
    }

    func markAllBoardThreadsAsRead() {
        markThreadsAsRead(boardsByPath.values.flatMap(\.threads))
    }

    func applyBoardThreadListState(to thread: BoardThread) {
        refreshThreadUnreadState(for: thread)
    }

    func applyRemoteThreadActivity(to thread: BoardThread, latestReplyChanged: Bool) {
        if latestReplyChanged {
            boardReadIDs.remove(thread.uuid)
            persistBoardReadIDs()
        }
        refreshThreadUnreadState(for: thread)
    }

    func markOwnThreadAsRead(_ thread: BoardThread, postUUID: String? = nil) {
        boardReadIDs.insert(thread.uuid)
        if let latestReplyUUID = thread.lastReplyUUID {
            boardReadIDs.insert(latestReplyUUID)
        }
        if let postUUID {
            boardReadIDs.insert(postUUID)
        }
        persistBoardReadIDs()
        refreshThreadUnreadState(for: thread)
    }

    func markSelectedThreadAsReadIfVisible() {
        guard
            let boardPath = selectedBoardPath,
            let threadUUID = selectedThreadUUID,
            let thread = thread(boardPath: boardPath, uuid: threadUUID),
            connectionController.shouldAutoMarkBoardThreadAsRead(in: self, thread: thread)
        else {
            return
        }

        markThreadAsRead(thread)
    }

    func appendChat(_ chat: Chat) {
        guard !chats.contains(where: { $0.id == chat.id }) else {
            return
        }
        chats.append(chat)
    }

    func appendPrivateChat(_ chat: Chat) {
        guard private_chats.contains(where: { $0.id == chat.id }) == false else {
            return
        }
        private_chats.append(chat)
    }

    func removePrivateChat(_ chatID: UInt32) {
        chat(withID: chatID)?.clearAllTyping()
        private_chats.removeAll { $0.id == chatID }

        if selectedChatID == chatID {
            selectedChatID = 1
        }
    }

    func chat(withID chatID: UInt32) -> Chat? {
        let publicChat = chats.first(where: { $0.id == chatID })
        let privateChat = private_chats.first(where: { $0.id == chatID })

        if let publicChat {
            return publicChat
        }

        if let privateChat {
            return privateChat
        }

        return nil
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
            userID: user.id,
            login: user.login.isEmpty ? nil : user.login
        )
        selectedMessageConversationID = conversation.id
        selectedTab = .messages
        resetUnreads(conversation)
        persistMessages()
        return conversation
    }

    func openOfflineMessageConversation(with offlineUser: OfflineUser) -> MessageConversation {
        let conversation = ensureDirectConversation(
            nick: offlineUser.nick,
            userID: nil,
            login: offlineUser.login
        )
        selectedMessageConversationID = conversation.id
        selectedTab = .messages
        resetUnreads(conversation)
        persistMessages()
        return conversation
    }

    func ensureDirectConversation(
        nick: String,
        userID: UInt32?,
        login: String? = nil
    ) -> MessageConversation {
        // 1. Match by login (most stable — survives session reconnects)
        if let login, !login.isEmpty,
           let conversation = messageConversations.first(where: {
               $0.kind == .direct && $0.participantLogin == login
           }) {
            if let userID { conversation.participantUserID = userID }
            let isPlaceholderNick = nick.hasPrefix("User #")
            if !isPlaceholderNick && conversation.participantNick != nick {
                conversation.participantNick = nick
                conversation.title = nick
            }
            return conversation
        }

        // 2. Match by userID (survives nick changes within a session)
        if let userID, let conversation = messageConversations.first(where: {
            $0.kind == .direct && $0.participantUserID == userID
        }) {
            if let login, !login.isEmpty { conversation.participantLogin = login }
            let isPlaceholderNick = nick.hasPrefix("User #")
            if !isPlaceholderNick && conversation.participantNick != nick {
                conversation.participantNick = nick
                conversation.title = nick
            }
            return conversation
        }

        // 3. Fallback: match by nick
        if let conversation = messageConversations.first(where: {
            $0.kind == .direct && $0.participantNick == nick
        }) {
            if let userID { conversation.participantUserID = userID }
            if let login, !login.isEmpty { conversation.participantLogin = login }
            return conversation
        }

        // 4. Create new
        let conversation = MessageConversation(
            kind: .direct,
            title: nick,
            participantNick: nick,
            participantUserID: userID,
            participantLogin: login
        )
        messageConversations.append(conversation)
        sortMessageConversations()
        persistMessages()
        return conversation
    }

    var currentLogin: String? {
        if let config = connectionController.configuration(for: id) {
            return config.login.isEmpty ? nil : config.login
        }
        let urlLogin = connection?.url.login ?? ""
        return urlLogin.isEmpty ? nil : urlLogin
    }

    /// Stable per-server account identifier ("<host>|<login>") used to scope
    /// the offline-messaging Keychain entry. Returning a host-qualified value
    /// avoids collisions when the same login exists on multiple Wired servers.
    private var keypairAccountID: String? {
        if let configuration = connectionController.configuration(for: id) {
            let host = configuration.hostname.lowercased()
            let login = configuration.login.lowercased()
            guard !host.isEmpty, !login.isEmpty else { return nil }
            return "\(host)|\(login)"
        }
        if let url = connection?.url {
            let host = url.hostname.lowercased()
            let login = url.login.lowercased()
            guard !host.isEmpty, !login.isEmpty else { return nil }
            return "\(host)|\(login)"
        }
        return nil
    }

    func uploadPublicKey() async {
        guard let accountID = keypairAccountID else { return }
        let keyData = OfflineMessageKeyManager.shared
            .loadOrCreateKeyPair(forAccount: accountID, legacyUsername: currentLogin)
            .publicKey.rawRepresentation
        let msg = P7Message(withName: "wired.user.set_public_key", spec: spec)
        msg.addParameter(field: "wired.user.public_key", value: keyData)
        _ = try? await send(msg)
    }

    func receiveOfflineMessage(fromLogin senderLogin: String, senderNick: String?, text: String, date: Date, isEncrypted: Bool) {
        let displayNick = senderNick ?? senderLogin
        let conversation = ensureDirectConversation(nick: displayNick, userID: nil, login: senderLogin)

        var displayText = text
        if isEncrypted {
            // Try the host-scoped key first, then fall back to the legacy login-only
            // slot for any keypair created before account-scoping was introduced.
            let candidates: [Curve25519.KeyAgreement.PrivateKey] = [
                keypairAccountID.flatMap { OfflineMessageKeyManager.shared.privateKey(forAccount: $0) },
                currentLogin.flatMap { OfflineMessageKeyManager.shared.privateKey(forAccount: $0) }
            ].compactMap { $0 }

            if let decrypted = candidates.lazy.compactMap({
                try? OfflineMessageCrypto.decrypt(blob: text, privateKey: $0)
            }).first {
                displayText = decrypted
            } else {
                displayText = "[Encrypted message — decryption key not available]"
            }
        }

        conversation.messages.append(
            MessageEvent(
                id: UUID(),
                senderNick: displayNick,
                senderUserID: nil,
                senderIcon: nil,
                text: displayText,
                date: date,
                isFromCurrentUser: false,
                attachments: []
            )
        )
        conversation.unreadMessagesCount += 1
        sortMessageConversations()
        if selectedTab != .messages {
            connectionController.updateNotificationsBadge()
        }
        persistMessages()
    }

    func receiveOfflineUserList(login: String, nick: String?) {
        guard !offlineUsers.contains(where: { $0.login == login }) else { return }
        offlineUsers.append(OfflineUser(login: login, nick: nick))
        offlineUsers.sort { $0.nick.localizedCaseInsensitiveCompare($1.nick) == .orderedAscending }
    }

    func sendPrivateMessage(_ text: String, in conversation: MessageConversation, attachments: [ChatDraftAttachment] = []) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty else { return }
        guard conversation.kind == .direct else { return }

        // If recipient is offline and we have their login, send as offline message
        if resolvedRecipientUserID(for: conversation) == nil,
           let login = conversation.participantLogin,
           hasPrivilege("wired.account.message.send_offline_messages") {

            let offlineMsg = P7Message(withName: "wired.message.send_offline_message", spec: spec)
            offlineMsg.addParameter(field: "wired.message.offline.recipient_login", value: login)

            let keyRequest = P7Message(withName: "wired.user.get_public_key", spec: spec)
            keyRequest.addParameter(field: "wired.message.offline.recipient_login", value: login)

            guard let keyResponse = try? await send(keyRequest),
                  let pubKeyData = keyResponse.data(forField: "wired.user.public_key"),
                  !pubKeyData.isEmpty else {
                throw WiredError(
                    withTitle: "Offline Message",
                    message: "This user hasn't enabled offline messaging yet. They need to connect at least once with a compatible client to register their encryption key."
                )
            }

            guard let encryptedBlob = try? OfflineMessageCrypto.encrypt(
                plaintext: trimmed,
                recipientPublicKeyData: pubKeyData
            ) else {
                throw WiredError(withTitle: "Offline Message", message: "Failed to encrypt message.")
            }

            offlineMsg.addParameter(field: "wired.message.message", value: encryptedBlob)
            offlineMsg.addParameter(field: "wired.message.offline.encrypted", value: true)

            if let response = try await send(offlineMsg), response.name == "wired.error" {
                throw WiredError(message: response)
            }
            appendOwnPrivateMessage(trimmed, to: conversation)
            return
        }

        guard let recipientUserID = resolvedRecipientUserID(for: conversation) else {
            throw WiredError(withTitle: "Private Message", message: "User is offline.")
        }

        try ChatDraftAttachment.validateDraftCollection(attachments)

        var attachmentIDs: [String] = []
        attachmentIDs.reserveCapacity(attachments.count)

        for attachment in attachments {
            attachmentIDs.append(try await uploadPrivateMessageAttachment(attachment, toUserID: recipientUserID))
        }

        let message = P7Message(withName: "wired.message.send_message", spec: spec)
        message.addParameter(field: "wired.user.id", value: recipientUserID)
        message.addParameter(field: "wired.message.message", value: trimmed)
        if !attachmentIDs.isEmpty {
            message.addParameter(field: "wired.attachment.ids", value: attachmentIDs)
        }

        if let response = try await send(message), response.name == "wired.error" {
            throw WiredError(message: response)
        }

        let descriptors = zip(attachments, attachmentIDs).map { attachment, id in
            ChatAttachmentDescriptor(
                id: id,
                name: attachment.fileName,
                mediaType: attachment.mediaType,
                size: attachment.size,
                sha256: "",
                inlinePreview: attachment.isImage,
                width: nil,
                height: nil
            )
        }

        appendOwnPrivateMessage(trimmed, attachments: descriptors, to: conversation)
    }

    func sendBroadcastMessage(_ text: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let message = P7Message(withName: "wired.message.send_broadcast", spec: spec)
        message.addParameter(field: "wired.message.broadcast", value: trimmed)

        if let response = try await send(message), response.name == "wired.error" {
            throw WiredError(message: response)
        }

        let conversation = ensureBroadcastConversation()
        appendOwnMessage(trimmed, to: conversation, isBroadcast: true)
    }

    func receivePrivateMessage(from userID: UInt32, text: String, attachments: [ChatAttachmentDescriptor] = []) {
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
            attachments: attachments,
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

    func deleteMessageConversation(withID conversationID: UUID) {
        guard let index = messageConversations.firstIndex(where: { $0.id == conversationID }) else { return }

        messageConversations.remove(at: index)

        if selectedMessageConversationID == conversationID {
            selectedMessageConversationID = messageConversations.first?.id
        }

        connectionController.updateNotificationsBadge()
        persistMessages()
    }

    func canSendMessage(to conversation: MessageConversation) -> Bool {
        switch conversation.kind {
        case .broadcast:
            return hasPrivilege("wired.account.message.broadcast")
        case .direct:
            guard hasPrivilege("wired.account.message.send_messages") else { return false }
            if resolvedRecipientUserID(for: conversation) != nil { return true }
            // Allow sending as offline message if recipient has a known login and privilege is granted
            return conversation.participantLogin != nil
                && hasPrivilege("wired.account.message.send_offline_messages")
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

    private func appendOwnPrivateMessage(_ text: String, attachments: [ChatAttachmentDescriptor] = [], to conversation: MessageConversation) {
        appendOwnMessage(text, attachments: attachments, to: conversation, isBroadcast: false)
    }

    private func appendOwnMessage(_ text: String, attachments: [ChatAttachmentDescriptor] = [], to conversation: MessageConversation, isBroadcast: Bool) {
        let me = onlineUser(withID: userID)
        let nick = me?.nick ?? "You"
        let icon = me?.icon
        conversation.messages.append(
            MessageEvent(
                senderNick: nick,
                senderUserID: userID,
                senderIcon: icon,
                text: text,
                isFromCurrentUser: true,
                attachments: attachments
            )
        )
        if selectedMessageConversationID == nil || selectedMessageConversationID == conversation.id {
            selectedMessageConversationID = conversation.id
        }
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
        attachments: [ChatAttachmentDescriptor] = [],
        to conversation: MessageConversation
    ) {
        conversation.messages.append(
            MessageEvent(
                senderNick: nick,
                senderUserID: userID,
                senderIcon: icon,
                text: text,
                isFromCurrentUser: false,
                attachments: attachments
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
                            isFromCurrentUser: storedMessage.isFromCurrentUser,
                            attachments: decodeStoredAttachmentDescriptors(from: storedMessage.attachmentDescriptorsData)
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
            // --- Private conversations (upsert) ---
            let privateDescriptor = FetchDescriptor<StoredPrivateConversation>(
                predicate: #Predicate<StoredPrivateConversation> { $0.connectionKey == key }
            )
            let existingPrivateConversations = try modelContext.fetch(privateDescriptor)
            let inMemoryPrivateIDs = Set(messageConversations.filter { $0.kind == .direct }.map { $0.id })

            for stored in existingPrivateConversations where !inMemoryPrivateIDs.contains(stored.conversationID) {
                modelContext.delete(stored)
            }

            for conversation in messageConversations where conversation.kind == .direct {
                let storedConversation: StoredPrivateConversation
                if let existing = existingPrivateConversations.first(where: { $0.conversationID == conversation.id }) {
                    existing.title = conversation.title
                    existing.participantNick = conversation.participantNick
                    existing.participantUserID = conversation.participantUserID
                    existing.unreadMessagesCount = conversation.unreadMessagesCount
                    existing.lastUpdatedAt = conversation.lastMessageDate ?? .distantPast
                    storedConversation = existing
                } else {
                    let new = StoredPrivateConversation(
                        conversationID: conversation.id,
                        connectionKey: key,
                        title: conversation.title,
                        participantNick: conversation.participantNick,
                        participantUserID: conversation.participantUserID,
                        unreadMessagesCount: conversation.unreadMessagesCount,
                        lastUpdatedAt: conversation.lastMessageDate ?? .distantPast
                    )
                    modelContext.insert(new)
                    storedConversation = new
                }

                let existingMessageIDs = Set(storedConversation.messages.map { $0.eventID })
                for message in conversation.messages where !existingMessageIDs.contains(message.id) {
                    let storedMessage = StoredPrivateMessage(
                        eventID: message.id,
                        senderNick: message.senderNick,
                        senderUserID: message.senderUserID,
                        senderIcon: message.senderIcon,
                        text: message.text,
                        date: message.date,
                        isFromCurrentUser: message.isFromCurrentUser,
                        attachmentDescriptorsData: encodeStoredAttachmentDescriptors(message.attachments),
                        conversation: storedConversation
                    )
                    modelContext.insert(storedMessage)
                }
            }

            // --- Broadcast conversations (upsert) ---
            let broadcastDescriptor = FetchDescriptor<StoredBroadcastConversation>(
                predicate: #Predicate<StoredBroadcastConversation> { $0.connectionKey == key }
            )
            let existingBroadcastConversations = try modelContext.fetch(broadcastDescriptor)
            let inMemoryBroadcastIDs = Set(messageConversations.filter { $0.kind == .broadcast }.map { $0.id })

            for stored in existingBroadcastConversations where !inMemoryBroadcastIDs.contains(stored.conversationID) {
                modelContext.delete(stored)
            }

            for conversation in messageConversations where conversation.kind == .broadcast {
                let storedConversation: StoredBroadcastConversation
                if let existing = existingBroadcastConversations.first(where: { $0.conversationID == conversation.id }) {
                    existing.title = conversation.title
                    existing.unreadMessagesCount = conversation.unreadMessagesCount
                    existing.lastUpdatedAt = conversation.lastMessageDate ?? .distantPast
                    storedConversation = existing
                } else {
                    let new = StoredBroadcastConversation(
                        conversationID: conversation.id,
                        connectionKey: key,
                        title: conversation.title,
                        unreadMessagesCount: conversation.unreadMessagesCount,
                        lastUpdatedAt: conversation.lastMessageDate ?? .distantPast
                    )
                    modelContext.insert(new)
                    storedConversation = new
                }

                let existingMessageIDs = Set(storedConversation.messages.map { $0.eventID })
                for message in conversation.messages where !existingMessageIDs.contains(message.id) {
                    let storedMessage = StoredBroadcastMessage(
                        eventID: message.id,
                        senderNick: message.senderNick,
                        senderUserID: message.senderUserID,
                        senderIcon: message.senderIcon,
                        text: message.text,
                        date: message.date,
                        isFromCurrentUser: message.isFromCurrentUser,
                        conversation: storedConversation
                    )
                    modelContext.insert(storedMessage)
                }
            }

            // --- Selection ---
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

    private func encodeStoredAttachmentDescriptors(_ descriptors: [ChatAttachmentDescriptor]) -> Data? {
        guard !descriptors.isEmpty else { return nil }
        return try? JSONEncoder().encode(descriptors)
    }

    private func decodeStoredAttachmentDescriptors(from data: Data?) -> [ChatAttachmentDescriptor] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([ChatAttachmentDescriptor].self, from: data)) ?? []
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

    // MARK: - Chat History Archiving

    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    func archiveChatMessage(_ event: ChatEvent, chatID: UInt32, chatName: String) {
        guard let modelContext, let key = persistenceKey() else { return }
        let stored = StoredChatMessage(
            eventID: event.id,
            connectionKey: key,
            chatID: chatID,
            chatName: chatName,
            senderNick: event.user.nick,
            senderUserID: event.user.id,
            senderIcon: event.user.icon,
            senderColor: event.user.color,
            text: event.text,
            type: event.type.rawStorageValue,
            date: event.date,
            dayKey: Self.dayKeyFormatter.string(from: event.date),
            isFromCurrentUser: event.user.id == userID
        )
        modelContext.insert(stored)
        do {
            try modelContext.save()
        } catch {
            print("[ChatHistory] archive failed:", error)
        }
    }

    func checkArchiveAvailability(for chat: Chat) {
        guard let modelContext, let key = persistenceKey() else { return }
        guard UserDefaults.standard.bool(forKey: "ArchiveChatHistory") else { return }
        let chatID = chat.id
        do {
            var descriptor = FetchDescriptor<StoredChatMessage>(
                predicate: #Predicate<StoredChatMessage> {
                    $0.connectionKey == key && $0.chatID == chatID
                }
            )
            descriptor.fetchLimit = 1
            let count = try modelContext.fetchCount(descriptor)
            chat.hasMoreHistory = count > 0
        } catch {
            print("[ChatHistory] checkArchiveAvailability failed:", error)
        }
    }

    func loadArchivedChatMessages(for chat: Chat, before date: Date, limit: Int = 100) -> (messages: [ChatEvent], hasMore: Bool) {
        guard let modelContext, let key = persistenceKey() else { return ([], false) }
        let chatID = chat.id
        do {
            var descriptor = FetchDescriptor<StoredChatMessage>(
                predicate: #Predicate<StoredChatMessage> {
                    $0.connectionKey == key && $0.chatID == chatID && $0.date < date
                },
                sortBy: [SortDescriptor(\StoredChatMessage.date, order: .reverse)]
            )
            descriptor.fetchLimit = limit + 1
            let results = try modelContext.fetch(descriptor)
            let hasMore = results.count > limit
            let batch = Array((hasMore ? Array(results.prefix(limit)) : results).reversed())
            let events = batch.map { stored -> ChatEvent in
                let user = User(
                    id: stored.senderUserID,
                    nick: stored.senderNick,
                    icon: stored.senderIcon ?? Data(),
                    idle: false
                )
                user.color = stored.senderColor
                let event = ChatEvent(
                    chat: chat,
                    user: user,
                    type: ChatEventType(rawStorageValue: stored.type),
                    text: stored.text,
                    date: stored.date
                )
                event.isFromCurrentUser = stored.isFromCurrentUser
                return event
            }
            return (events, hasMore)
        } catch {
            print("[ChatHistory] loadArchivedChatMessages failed:", error)
            return ([], false)
        }
    }

    func searchArchivedMessages(for chat: Chat, matching query: String, limit: Int = 200) -> [ChatEvent] {
        guard let modelContext, let key = persistenceKey() else { return [] }
        let chatID = chat.id
        do {
            let descriptor = FetchDescriptor<StoredChatMessage>(
                predicate: #Predicate<StoredChatMessage> {
                    $0.connectionKey == key && $0.chatID == chatID
                },
                sortBy: [SortDescriptor(\StoredChatMessage.date, order: .forward)]
            )
            let results = try modelContext.fetch(descriptor)
            let matched = results.filter {
                $0.senderNick.localizedStandardContains(query) || $0.text.localizedStandardContains(query)
            }
            return matched.prefix(limit).map { stored in
                let user = User(
                    id: stored.senderUserID,
                    nick: stored.senderNick,
                    icon: stored.senderIcon ?? Data(),
                    idle: false
                )
                user.color = stored.senderColor
                let event = ChatEvent(
                    chat: chat,
                    user: user,
                    type: ChatEventType(rawStorageValue: stored.type),
                    text: stored.text,
                    date: stored.date
                )
                event.isFromCurrentUser = stored.isFromCurrentUser
                return event
            }
        } catch {
            print("[ChatHistory] searchArchivedMessages failed:", error)
            return []
        }
    }

    private func onlineUser(withID userID: UInt32) -> User? {
        (chats + private_chats)
            .flatMap(\.users)
            .first(where: { $0.id == userID })
    }

    private func resolvedRecipientUserID(for conversation: MessageConversation) -> UInt32? {
        guard conversation.kind == .direct else { return nil }
        guard let nick = conversation.participantNick else { return nil }

        // Check cached ID — but reject if it's our own ID (stale from a previous session)
        if let knownID = conversation.participantUserID,
           knownID != userID,
           onlineUser(withID: knownID) != nil {
            return knownID
        }

        if let user = (chats + private_chats)
            .flatMap(\.users)
            .first(where: { $0.nick == nick && $0.id != userID }) {
            conversation.participantUserID = user.id
            return user.id
        }

        return nil
    }

    // MARK: -

    func send(_ message: P7Message) async throws -> P7Message? {
        guard connection != nil else {
            throw AsyncConnectionError.notConnected
        }

        do {
            return try await connectionController.socketClient.send(message, on: id)
        } catch {
            throw normalizedRequestError(error)
        }
    }

    // MARK: -

    func getUserInfo(_ userID: UInt32) {
        Task {
            showInfosUserID = userID
            await refreshUserInfo(userID, openPopover: true)
        }
    }

    func refreshUserInfo(_ userID: UInt32, openPopover: Bool = false) async {
        let message = P7Message(withName: "wired.user.get_info", spec: spec)
        message.addParameter(field: "wired.user.id", value: userID)

        do {
            if let response = try await send(message), response.name == "wired.user.info" {
                await connectionController.updateUserInfo(from: response, in: self)
                if openPopover && !showInfos {
                    showInfos = true
                }
            }
        } catch let error {
            lastError = error
        }
    }

    func disconnectUser(userID: UInt32, reason: String) async throws {
        let message = P7Message(withName: "wired.user.disconnect_user", spec: spec)
        message.addParameter(field: "wired.user.id", value: userID)
        message.addParameter(field: "wired.user.disconnect_message", value: reason)
        _ = try await send(message)
    }

    func fetchMonitoredUsers() async throws -> [MonitoredUser] {
        let message = P7Message(withName: "wired.user.get_users", spec: spec)
        let connection = try requireAsyncConnection()

        do {
            var users: [MonitoredUser] = []

            for try await response in try connection.sendAndWaitMany(message) {
                switch response.name {
                case "wired.user.user_list":
                    guard let user = monitoredUser(from: response) else { continue }
                    users.append(user)

                case "wired.error":
                    throw WiredError(message: response)

                default:
                    continue
                }
            }

            return users.sorted { lhs, rhs in
                if lhs.isDownloading != rhs.isDownloading {
                    return lhs.isDownloading && !rhs.isDownloading
                }

                if lhs.isUploading != rhs.isUploading {
                    return lhs.isUploading && !rhs.isUploading
                }

                return lhs.nick.localizedCaseInsensitiveCompare(rhs.nick) == .orderedAscending
            }
        } catch {
            throw normalizedRequestError(error)
        }
    }

    func banUser(userID: UInt32, reason: String, expirationDate: Date?) async throws {
        let message = P7Message(withName: "wired.user.ban_user", spec: spec)
        message.addParameter(field: "wired.user.id", value: userID)
        message.addParameter(field: "wired.user.disconnect_message", value: reason)
        if let expirationDate {
            message.addParameter(field: "wired.banlist.expiration_date", value: expirationDate)
        }
        _ = try await send(message)
    }

    func kickUser(chatID: UInt32, userID: UInt32, reason: String) async throws {
        let message = P7Message(withName: "wired.chat.kick_user", spec: spec)
        message.addParameter(field: "wired.chat.id", value: chatID)
        message.addParameter(field: "wired.user.id", value: userID)
        message.addParameter(field: "wired.user.disconnect_message", value: reason)
        _ = try await send(message)
    }

    private func monitoredUser(from message: P7Message) -> MonitoredUser? {
        guard
            let id = message.uint32(forField: "wired.user.id"),
            let nick = message.string(forField: "wired.user.nick"),
            let icon = message.data(forField: "wired.user.icon"),
            let idle = message.bool(forField: "wired.user.idle")
        else {
            return nil
        }

        let activeTransfer: UserActiveTransfer?
        if let rawType = message.enumeration(forField: "wired.transfer.type")
            ?? message.uint32(forField: "wired.transfer.type"),
           let type = UserActiveTransferType(rawValue: rawType),
           let path = message.string(forField: "wired.file.path") {
            activeTransfer = UserActiveTransfer(
                type: type,
                path: path,
                dataSize: message.uint64(forField: "wired.transfer.data_size") ?? 0,
                rsrcSize: message.uint64(forField: "wired.transfer.rsrc_size") ?? 0,
                transferred: message.uint64(forField: "wired.transfer.transferred") ?? 0,
                speed: message.uint32(forField: "wired.transfer.speed") ?? 0,
                queuePosition: Int(message.uint32(forField: "wired.transfer.queue_position") ?? 0)
            )
        } else {
            activeTransfer = nil
        }

        return MonitoredUser(
            id: id,
            nick: nick,
            status: message.string(forField: "wired.user.status"),
            icon: icon,
            idle: idle,
            color: message.enumeration(forField: "wired.account.color")
                ?? message.uint32(forField: "wired.account.color")
                ?? 0,
            idleTime: message.date(forField: "wired.user.idle_time"),
            activeTransfer: activeTransfer
        )
    }

    func fetchBans() async throws -> [BanListEntry] {
        let message = P7Message(withName: "wired.banlist.get_bans", spec: spec)
        let connection = try requireAsyncConnection()

        do {
            let stream = try connection.sendAndWaitMany(message)
            var bans: [BanListEntry] = []

            for try await response in stream {
                guard response.name == "wired.banlist.list" else { continue }
                guard let ipPattern = response.string(forField: "wired.banlist.ip") else { continue }

                bans.append(
                    BanListEntry(
                        ipPattern: ipPattern,
                        expirationDate: response.date(forField: "wired.banlist.expiration_date")
                    )
                )
            }

            return bans.sorted {
                switch ($0.expirationDate, $1.expirationDate) {
                case let (lhs?, rhs?):
                    if lhs != rhs { return lhs < rhs }
                case (nil, .some):
                    return true
                case (.some, nil):
                    return false
                default:
                    break
                }

                return $0.ipPattern.localizedStandardCompare($1.ipPattern) == .orderedAscending
            }
        } catch {
            throw normalizedRequestError(error)
        }
    }

    func addBan(ipPattern: String, expirationDate: Date?) async throws {
        let message = P7Message(withName: "wired.banlist.add_ban", spec: spec)
        message.addParameter(field: "wired.banlist.ip", value: ipPattern)
        if let expirationDate {
            message.addParameter(field: "wired.banlist.expiration_date", value: expirationDate)
        }
        _ = try await send(message)
    }

    func deleteBan(ipPattern: String, expirationDate: Date?) async throws {
        let message = P7Message(withName: "wired.banlist.delete_ban", spec: spec)
        message.addParameter(field: "wired.banlist.ip", value: ipPattern)
        if let expirationDate {
            message.addParameter(field: "wired.banlist.expiration_date", value: expirationDate)
        }
        _ = try await send(message)
    }

    func fetchFirstEventTime() async throws -> Date {
        let message = P7Message(withName: "wired.event.get_first_time", spec: spec)

        do {
            guard let response = try await send(message) else {
                return Date(timeIntervalSince1970: 0)
            }

            guard response.name == "wired.event.first_time" else {
                return Date(timeIntervalSince1970: 0)
            }

            return response.date(forField: "wired.event.first_time") ?? Date(timeIntervalSince1970: 0)
        } catch {
            throw normalizedRequestError(error)
        }
    }

    func fetchCurrentEvents(limit: UInt32 = 1000) async throws -> [WiredServerEventRecord] {
        let message = P7Message(withName: "wired.event.get_events", spec: spec)
        message.addParameter(field: "wired.event.last_event_count", value: limit)
        return try await fetchEvents(using: message)
    }

    func fetchArchivedEvents(from fromTime: Date, numberOfDays: UInt32 = 7) async throws -> [WiredServerEventRecord] {
        let message = P7Message(withName: "wired.event.get_events", spec: spec)
        message.addParameter(field: "wired.event.from_time", value: fromTime)
        message.addParameter(field: "wired.event.number_of_days", value: numberOfDays)
        return try await fetchEvents(using: message)
    }

    func subscribeToEvents() async throws {
        let message = P7Message(withName: "wired.event.subscribe", spec: spec)
        _ = try await send(message)
    }

    func unsubscribeFromEvents() async throws {
        let message = P7Message(withName: "wired.event.unsubscribe", spec: spec)
        _ = try await send(message)
    }

    func deleteEvents(from fromTime: Date?, to toTime: Date?) async throws {
        let message = P7Message(withName: "wired.event.delete_events", spec: spec)
        if let fromTime {
            message.addParameter(field: "wired.event.from_time", value: fromTime)
        }
        if let toTime {
            message.addParameter(field: "wired.event.to_time", value: toTime)
        }
        _ = try await send(message)
    }

    private func fetchEvents(using message: P7Message) async throws -> [WiredServerEventRecord] {
        let connection = try requireAsyncConnection()

        do {
            let stream = try connection.sendAndWaitMany(message)
            var events: [WiredServerEventRecord] = []

            for try await response in stream {
                guard response.name == "wired.event.event_list" else { continue }
                guard let event = WiredServerEventRecord(message: response) else { continue }
                events.append(event)
            }

            return events
        } catch {
            throw normalizedRequestError(error)
        }
    }

    // MARK: - Log (wired.log.*)

    /// Fetch the server log buffer via `wired.log.get_log`.
    func fetchLog() async throws -> [WiredLogEntry] {
        let connection = try requireAsyncConnection()

        do {
            let request = P7Message(withName: "wired.log.get_log", spec: spec)
            let stream  = try connection.sendAndWaitMany(request)
            var entries: [WiredLogEntry] = []

            for try await response in stream {
                guard response.name == "wired.log.list" else { continue }
                guard let entry = WiredLogEntry(message: response) else { continue }
                entries.append(entry)
            }

            return entries
        } catch {
            throw normalizedRequestError(error)
        }
    }

    /// Subscribe to live log broadcasts (`wired.log.subscribe`).
    func subscribeToLog() async throws {
        let message = P7Message(withName: "wired.log.subscribe", spec: spec)
        _ = try await send(message)
    }

    /// Unsubscribe from live log broadcasts (`wired.log.unsubscribe`).
    func unsubscribeFromLog() async throws {
        let message = P7Message(withName: "wired.log.unsubscribe", spec: spec)
        _ = try await send(message)
    }

    // MARK: -

    func sendChatMessage(_ chatID: UInt32, _ text: String, attachments: [ChatDraftAttachment] = []) async throws -> P7Message? {
        if text.starts(with: "/") {
            if !attachments.isEmpty {
                throw WiredError(withTitle: "Attachment", message: "Attachments are currently supported only for regular chat messages.")
            }

            if text == ChatCommand.clear.rawValue {
                await MainActor.run {
                    self.clearChat(chatID)
                }
                return nil
            }

            if text == "/generate" {
                await MainActor.run { self.generateDebugMessages(chatID) }
                return nil
            }

            if let message = self.chatCommand(chatID, text) {
                return try await self.send(message)
            }
        } else {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty || !attachments.isEmpty else { return nil }

            try ChatDraftAttachment.validateDraftCollection(attachments)

            var attachmentIDs: [String] = []
            attachmentIDs.reserveCapacity(attachments.count)

            for attachment in attachments {
                attachmentIDs.append(try await uploadChatAttachment(attachment, toChatID: chatID))
            }

            let message = P7Message(withName: "wired.chat.send_say", spec: spec)
            message.addParameter(field: "wired.chat.id", value: chatID)
            message.addParameter(field: "wired.chat.say", value: trimmed)
            if !attachmentIDs.isEmpty {
                message.addParameter(field: "wired.attachment.ids", value: attachmentIDs)
            }
            return try await self.send(message)
        }

        return nil
    }

    func addChatDraftAttachment(_ fileURL: URL, for chatID: UInt32) throws {
        let attachment = try ChatDraftAttachment(fileURL: fileURL)
        var attachments = chatDraftAttachments[chatID] ?? []

        guard !attachments.contains(where: { $0.fileURL == attachment.fileURL }) else { return }

        attachments.append(attachment)
        try ChatDraftAttachment.validateDraftCollection(attachments)
        chatDraftAttachments[chatID] = attachments
    }

    func removeChatDraftAttachment(_ attachment: ChatDraftAttachment, for chatID: UInt32) {
        guard var attachments = chatDraftAttachments[chatID] else { return }

        attachments.removeAll { $0.id == attachment.id }

        if attachments.isEmpty {
            chatDraftAttachments.removeValue(forKey: chatID)
        } else {
            chatDraftAttachments[chatID] = attachments
        }
    }

    func clearChatDraftAttachments(for chatID: UInt32) {
        chatDraftAttachments.removeValue(forKey: chatID)
    }

    func addMessageDraftAttachment(_ fileURL: URL, for conversationID: UUID) throws {
        let attachment = try ChatDraftAttachment(fileURL: fileURL)
        var attachments = messageDraftAttachments[conversationID] ?? []

        guard !attachments.contains(where: { $0.fileURL == attachment.fileURL }) else { return }

        attachments.append(attachment)
        try ChatDraftAttachment.validateDraftCollection(attachments)
        messageDraftAttachments[conversationID] = attachments
    }

    func removeMessageDraftAttachment(_ attachment: ChatDraftAttachment, for conversationID: UUID) {
        guard var attachments = messageDraftAttachments[conversationID] else { return }

        attachments.removeAll { $0.id == attachment.id }

        if attachments.isEmpty {
            messageDraftAttachments.removeValue(forKey: conversationID)
        } else {
            messageDraftAttachments[conversationID] = attachments
        }
    }

    func clearMessageDraftAttachments(for conversationID: UUID) {
        messageDraftAttachments.removeValue(forKey: conversationID)
    }

    func imageData(for attachment: ChatAttachmentDescriptor) async throws -> Data {
        if attachment.inlinePreview {
            do {
                return try await previewData(for: attachment)
            } catch {
                return try await downloadChatAttachmentData(attachment)
            }
        }

        return try await downloadChatAttachmentData(attachment)
    }

    func previewData(for attachment: ChatAttachmentDescriptor) async throws -> Data {
        let message = P7Message(withName: "wired.attachment.get_preview", spec: spec)
        message.addParameter(field: "wired.attachment.id", value: attachment.id)

        guard let response = try await send(message) else {
            throw WiredError(withTitle: "Attachment", message: "No preview response from server.")
        }

        if response.name == "wired.error" {
            throw WiredError(message: response)
        }

        guard response.name == "wired.attachment.preview",
              let data = response.data(forField: "wired.attachment.data") else {
            throw WiredError(withTitle: "Attachment", message: "Invalid preview response from server.")
        }

        return data
    }

    func downloadChatAttachmentData(_ attachment: ChatAttachmentDescriptor) async throws -> Data {
        var offset: UInt64 = 0
        var collected = Data()
        var isComplete = false

        while !isComplete {
            let message = P7Message(withName: "wired.attachment.get_data", spec: spec)
            message.addParameter(field: "wired.attachment.id", value: attachment.id)
            message.addParameter(field: "wired.attachment.offset", value: offset)
            message.addParameter(field: "wired.attachment.length", value: UInt32(256 * 1024))

            guard let response = try await send(message) else {
                throw WiredError(withTitle: "Attachment", message: "No data response from server.")
            }

            if response.name == "wired.error" {
                throw WiredError(message: response)
            }

            guard response.name == "wired.attachment.data",
                  let chunk = response.data(forField: "wired.attachment.data") else {
                throw WiredError(withTitle: "Attachment", message: "Invalid attachment data response from server.")
            }

            collected.append(chunk)
            offset += UInt64(chunk.count)
            isComplete = response.bool(forField: "wired.attachment.complete") ?? false
        }

        return collected
    }

    private enum AttachmentUploadScope {
        case chat(UInt32)
        case direct(UInt32)
        case board(String)
        case thread(String)
        case post(String)
    }

    private func uploadAttachment(
        _ attachment: ChatDraftAttachment,
        scope: AttachmentUploadScope
    ) async throws -> String {
        let data = try Data(contentsOf: attachment.fileURL)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

        let create = P7Message(withName: "wired.attachment.create", spec: spec)
        switch scope {
        case .chat(let chatID):
            create.addParameter(field: "wired.chat.id", value: chatID)
        case .direct(let userID):
            create.addParameter(field: "wired.user.id", value: userID)
        case .board(let boardPath):
            create.addParameter(field: "wired.board.board", value: boardPath)
        case .thread(let threadUUID):
            create.addParameter(field: "wired.board.thread", value: threadUUID)
        case .post(let postUUID):
            create.addParameter(field: "wired.board.post", value: postUUID)
        }
        create.addParameter(field: "wired.attachment.name", value: attachment.fileName)
        create.addParameter(field: "wired.attachment.media_type", value: attachment.mediaType)
        create.addParameter(field: "wired.attachment.size", value: UInt64(data.count))
        create.addParameter(field: "wired.attachment.sha256", value: digest)

        guard let createResponse = try await send(create) else {
            throw WiredError(withTitle: "Attachment", message: "No response from server while creating attachment.")
        }

        if createResponse.name == "wired.error" {
            throw WiredError(message: createResponse)
        }

        guard createResponse.name == "wired.attachment.created",
              let attachmentID = createResponse.uuid(forField: "wired.attachment.id") else {
            throw WiredError(withTitle: "Attachment", message: "Invalid attachment creation response from server.")
        }

        var offset = 0
        let chunkSize = 256 * 1024

        while offset < data.count {
            let upperBound = min(offset + chunkSize, data.count)
            let chunk = data.subdata(in: offset..<upperBound)

            let upload = P7Message(withName: "wired.attachment.upload", spec: spec)
            upload.addParameter(field: "wired.attachment.id", value: attachmentID)
            upload.addParameter(field: "wired.attachment.offset", value: UInt64(offset))
            upload.addParameter(field: "wired.attachment.data", value: chunk)

            if let uploadResponse = try await send(upload), uploadResponse.name == "wired.error" {
                throw WiredError(message: uploadResponse)
            }

            offset = upperBound
        }

        let complete = P7Message(withName: "wired.attachment.complete", spec: spec)
        complete.addParameter(field: "wired.attachment.id", value: attachmentID)

        guard let completeResponse = try await send(complete) else {
            throw WiredError(withTitle: "Attachment", message: "No completion response from server.")
        }

        if completeResponse.name == "wired.error" {
            throw WiredError(message: completeResponse)
        }

        guard completeResponse.name == "wired.attachment.completed" else {
            throw WiredError(withTitle: "Attachment", message: "Invalid attachment completion response from server.")
        }

        return attachmentID
    }

    private func resolvedBoardMessagePayload(
        text: String,
        attachments: [ComposerAttachmentItem],
        uploadScope: AttachmentUploadScope
    ) async throws -> (text: String, attachmentIDs: [String], descriptors: [ChatAttachmentDescriptor]) {
        try ComposerAttachmentItem.validateCollection(attachments)

        let remoteDescriptors = attachments.compactMap(\.descriptor)
        let localDrafts = attachments.compactMap(\.draftAttachment)

        var attachmentIDs = remoteDescriptors.map(\.id)
        attachmentIDs.reserveCapacity(attachments.count)

        var draftIDMap: [String: String] = [:]
        draftIDMap.reserveCapacity(localDrafts.count)

        for attachment in localDrafts {
            let attachmentID = try await uploadAttachment(attachment, scope: uploadScope)
            attachmentIDs.append(attachmentID)
            draftIDMap[attachment.id.uuidString.lowercased()] = attachmentID
        }

        let descriptors = attachments.map { attachment -> ChatAttachmentDescriptor in
            switch attachment {
            case .remote(let descriptor):
                return descriptor
            case .local(let draft):
                let resolvedID = draftIDMap[draft.id.uuidString.lowercased()] ?? ""
                return ChatAttachmentDescriptor(
                    id: resolvedID,
                    name: draft.fileName,
                    mediaType: draft.mediaType,
                    size: draft.size,
                    sha256: "",
                    inlinePreview: draft.isImage,
                    width: nil,
                    height: nil
                )
            }
        }

        let resolvedText = text
            .resolvingDraftAttachmentReferences(using: draftIDMap)
            .removingUnboundAttachmentReferences(allowedAttachmentIDs: Set(attachmentIDs.map { $0.lowercased() }))
        return (resolvedText, attachmentIDs, descriptors)
    }

    private func uploadChatAttachment(_ attachment: ChatDraftAttachment, toChatID chatID: UInt32) async throws -> String {
        try await uploadAttachment(attachment, scope: .chat(chatID))
    }

    private func uploadPrivateMessageAttachment(_ attachment: ChatDraftAttachment, toUserID userID: UInt32) async throws -> String {
        try await uploadAttachment(attachment, scope: .direct(userID))
    }

    @MainActor
    private func clearChat(_ chatID: UInt32) {
        guard let chat = chat(withID: chatID) else { return }
        chat.messages.removeAll()
        chat.clearAllTyping()
    }

    @MainActor
    private func generateDebugMessages(_ chatID: UInt32) {
        guard let chat = chat(withID: chatID) else { return }

        let sender = chat.users.first(where: { $0.id == userID })
            ?? User(id: userID, nick: "Debug", icon: Data(), idle: false)
        let others = chat.users.filter { $0.id != userID }

        let words = [
            "lorem", "ipsum", "dolor", "sit", "amet", "consectetur",
            "adipiscing", "elit", "sed", "do", "eiusmod", "tempor",
            "incididunt", "ut", "labore", "et", "dolore", "magna",
            "aliqua", "enim", "ad", "minim", "veniam", "quis",
            "nostrud", "exercitation", "ullamco", "laboris", "nisi"
        ]

        var date = Date().addingTimeInterval(-Double(100 * 35))

        for i in 0..<100 {
            let wordCount = Int.random(in: 3...14)
            let text = (0..<wordCount).map { _ in words.randomElement()! }.joined(separator: " ")
            let user: User = (i % 3 == 0) ? (others.randomElement() ?? sender) : sender
            let event = ChatEvent(chat: chat, user: user, type: .say, text: text)
            event.date = date
            date = date.addingTimeInterval(Double.random(in: 15...60))
            chat.messages.append(event)
        }
    }

    // MARK: - Chat Messages

    func joinChat(_ chatID: UInt32) async throws {
        let message = P7Message(withName: "wired.chat.join_chat", spec: spec)

        message.addParameter(field: "wired.chat.id", value: chatID)

        _ = try await self.send(message)
    }

    func leaveChat(_ chatID: UInt32) async throws {
        let message = P7Message(withName: "wired.chat.leave_chat", spec: spec)

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
        let message = P7Message(withName: "wired.chat.create_chat", spec: spec)
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
        let message = P7Message(withName: "wired.chat.invite_user", spec: spec)
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
                let message = P7Message(withName: "wired.chat.decline_invitation", spec: spec)
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
        let message = P7Message(withName: "wired.chat.delete_public_chat", spec: spec)

        message.addParameter(field: "wired.chat.id", value: chatID)

        _ = try await self.send(message)
    }

    func setChatTopic(_ chatID: UInt32, topic: String) async throws {
        let message = P7Message(withName: "wired.chat.set_topic", spec: spec)

        message.addParameter(field: "wired.chat.id", value: chatID)
        message.addParameter(field: "wired.chat.topic.topic", value: topic)

        _ = try await self.send(message)
    }

    // MARK: - User Status Messages

    func setNickMessage(_ nick: String) -> P7Message? {
        let message = P7Message(withName: "wired.user.set_nick", spec: spec)
        message.addParameter(field: "wired.user.nick", value: nick)

        return message
    }

    func setStatusMessage(_ status: String) -> P7Message? {
        let message = P7Message(withName: "wired.user.set_status", spec: spec)
        message.addParameter(field: "wired.user.status", value: status)

        return message
    }

    func setIconMessage(_ icon: Data) -> P7Message? {
        let message = P7Message(withName: "wired.user.set_icon", spec: spec)

        message.addParameter(field: "wired.user.icon", value: icon)

        return message
    }

    // MARK: -

    private func chatCommand(_ chatID: UInt32, _ command: String) -> P7Message? {
        let comps = command.split(separator: " ", maxSplits: 1)
        guard let cmd = ChatCommand(rawValue: String(comps[0])) else { return nil }

        switch cmd {
        case .me:
            let value = command.deletingPrefix(String(comps[0]) + " ")
            guard !value.isEmpty, value != String(comps[0]) else { return nil }
            let message = P7Message(withName: "wired.chat.send_me", spec: spec)
            message.addParameter(field: "wired.chat.id", value: chatID)
            message.addParameter(field: "wired.chat.me", value: value)
            return message

        case .nick:
            let value = command.deletingPrefix(String(comps[0]) + " ")
            guard !value.isEmpty, value != String(comps[0]) else { return nil }
            return self.setNickMessage(value)

        case .status:
            let value = command.deletingPrefix(String(comps[0]) + " ")
            guard !value.isEmpty, value != String(comps[0]) else { return nil }
            return self.setStatusMessage(value)

        case .topic:
            let value = command.deletingPrefix(String(comps[0]) + " ")
            guard !value.isEmpty, value != String(comps[0]) else { return nil }
            let message = P7Message(withName: "wired.chat.set_topic", spec: spec)
            message.addParameter(field: "wired.chat.id", value: chatID)
            message.addParameter(field: "wired.chat.topic.topic", value: value)
            return message

        case .broadcast:
            let value = command.deletingPrefix(String(comps[0]) + " ")
            guard !value.isEmpty, value != String(comps[0]) else { return nil }
            let message = P7Message(withName: "wired.message.send_broadcast", spec: spec)
            message.addParameter(field: "wired.message.broadcast", value: value)
            return message

        case .help:
            let lines = ChatCommand.allCases.map { c -> String in
                let h = c.hint.isEmpty ? "" : " \(c.hint)"
                return "\(c.rawValue)\(h)\t\(c.usage)"
            }.joined(separator: "\n")
            let message = P7Message(withName: "wired.chat.send_say", spec: spec)
            message.addParameter(field: "wired.chat.id", value: chatID)
            message.addParameter(field: "wired.chat.say", value: "Chat commands:\n\n" + lines)
            return message

        case .afk:
            let message = P7Message(withName: "wired.user.set_idle", spec: spec)
            message.addParameter(field: "wired.user.idle", value: true)
            return message

        case .clear, .stats:
            return nil
        }
    }

    // MARK: - Board Messages

    func getBoards() async throws {
        try await withBoardNetworkActivity {
            let m = P7Message(withName: "wired.board.get_boards", spec: spec)
            _ = try await send(m)
        }
    }

    func subscribeBoards() async throws {
        try await withBoardNetworkActivity {
            let m = P7Message(withName: "wired.board.subscribe_boards", spec: spec)
            _ = try await send(m)
        }
    }

    func getAllThreads() async throws {
        try await withBoardNetworkActivity {
            allBoardThreadsLoaded = false
            for board in boardsByPath.values {
                board.threadsLoaded = false
                board.threads.removeAll()
            }

            let m = P7Message(withName: "wired.board.get_threads", spec: spec)
            if let response = try await send(m), response.name == "wired.error" {
                throw WiredError(message: response)
            }

            allBoardThreadsLoaded = true
            for board in boardsByPath.values {
                board.threadsLoaded = true
            }
        }
    }

    func getThreads(forBoard board: Board) async throws {
        try await withBoardNetworkActivity {
            board.threadsLoaded = false
            board.threads.removeAll()
            let m = P7Message(withName: "wired.board.get_threads", spec: spec)
            m.addParameter(field: "wired.board.board", value: board.path)
            if let response = try await send(m), response.name == "wired.error" {
                throw WiredError(message: response)
            }
            board.threadsLoaded = true
        }
    }

    func ensureThreadsLoaded(for board: Board) async {
        guard !board.threadsLoaded else { return }
        try? await getThreads(forBoard: board)
    }

    func getPosts(forThread thread: BoardThread) async throws {
        try await withBoardNetworkActivity {
            thread.postsLoaded = false
            thread.posts.removeAll()
            let m = P7Message(withName: "wired.board.get_thread", spec: spec)
            m.addParameter(field: "wired.board.thread", value: thread.uuid)
            _ = try await send(m)
        }
    }

    func clearBoardSearch() {
        boardSearchResults = []
        isSearchingBoards = false
    }

    func searchBoards(query: String, scopeBoardPath: String?) async throws {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let connection = connection as? AsyncConnection else {
            throw WiredError(withTitle: "Board Search", message: "Not connected.")
        }

        guard !trimmed.isEmpty else {
            clearBoardSearch()
            return
        }

        try await withBoardNetworkActivity {
            isSearchingBoards = true
            boardSearchResults = []

            let message = P7Message(withName: "wired.board.search", spec: spec)
            message.addParameter(field: "wired.board.query", value: trimmed)
            if let scopeBoardPath, !scopeBoardPath.isEmpty {
                message.addParameter(field: "wired.board.board", value: scopeBoardPath)
            }

            var results: [BoardSearchResult] = []

            do {
                for try await response in try connection.sendAndWaitMany(message) {
                    try Task.checkCancellation()
                    if response.name == "wired.board.search_list", let result = BoardSearchResult(response) {
                        results.append(result)
                    }
                }
                boardSearchResults = results
                isSearchingBoards = false
            } catch {
                isSearchingBoards = false
                if error is CancellationError {
                    return
                }
                throw error
            }
        }
    }

    func addThread(
        toBoard board: Board,
        subject: String,
        text: String,
        attachments: [ComposerAttachmentItem] = []
    ) async throws {
        try await withBoardNetworkActivity {
            let payload = try await resolvedBoardMessagePayload(
                text: text,
                attachments: attachments,
                uploadScope: .board(board.path)
            )
            let m = P7Message(withName: "wired.board.add_thread", spec: spec)
            m.addParameter(field: "wired.board.board", value: board.path)
            m.addParameter(field: "wired.board.subject", value: subject)
            m.addParameter(field: "wired.board.text", value: payload.text)
            if !payload.attachmentIDs.isEmpty {
                m.addParameter(field: "wired.attachment.ids", value: payload.attachmentIDs)
            }
            if let response = try await send(m), response.name == "wired.error" {
                throw WiredError(message: response)
            }
        }
    }

    func addPost(
        toThread thread: BoardThread,
        text: String,
        attachments: [ComposerAttachmentItem] = []
    ) async throws {
        try await withBoardNetworkActivity {
            let payload = try await resolvedBoardMessagePayload(
                text: text,
                attachments: attachments,
                uploadScope: .thread(thread.uuid)
            )
            let m = P7Message(withName: "wired.board.add_post", spec: spec)
            m.addParameter(field: "wired.board.thread", value: thread.uuid)
            m.addParameter(field: "wired.board.subject", value: thread.subject)
            m.addParameter(field: "wired.board.text", value: payload.text)
            if !payload.attachmentIDs.isEmpty {
                m.addParameter(field: "wired.attachment.ids", value: payload.attachmentIDs)
            }
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
                    text: payload.text,
                    nick: me?.nick ?? (connection?.nick ?? "Me"),
                    postDate: Date(),
                    icon: me?.icon,
                    isOwn: true,
                    attachments: payload.descriptors
                )
                post.isUnread = false
                thread.posts.append(post)
                pendingLocalPostUUIDByThread[thread.uuid] = localUUID
            }
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
        try await withBoardNetworkActivity {
            let m = P7Message(withName: "wired.board.add_board", spec: spec)
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
    }

    func listAccountUserNames() async throws -> [String] {
        guard let connection = connection as? AsyncConnection else {
            throw WiredError(withTitle: "Accounts", message: "Not connected.")
        }

        let message = P7Message(withName: "wired.account.list_users", spec: spec)
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

        let message = P7Message(withName: "wired.account.list_groups", spec: spec)
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
        try await withBoardNetworkActivity {
            let m = P7Message(withName: "wired.board.get_board_info", spec: spec)
            m.addParameter(field: "wired.board.board", value: path)

            guard let response = try await send(m) else {
                throw WiredError(withTitle: "Board", message: "No response from server.")
            }

            if response.name == "wired.error" {
                throw WiredError(message: response)
            }
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
        try await withBoardNetworkActivity {
            let m = P7Message(withName: "wired.board.set_board_info", spec: spec)
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
    }

    func deleteThread(uuid: String) async throws {
        try await withBoardNetworkActivity {
            let m = P7Message(withName: "wired.board.delete_thread", spec: spec)
            m.addParameter(field: "wired.board.thread", value: uuid)
            if let response = try await send(m), response.name == "wired.error" {
                throw WiredError(message: response)
            }
        }
    }

    func deletePost(uuid: String) async throws {
        try await withBoardNetworkActivity {
            let m = P7Message(withName: "wired.board.delete_post", spec: spec)
            m.addParameter(field: "wired.board.post", value: uuid)
            if let response = try await send(m), response.name == "wired.error" {
                throw WiredError(message: response)
            }
        }
    }

    func deleteBoard(path: String) async throws {
        try await withBoardNetworkActivity {
            let m = P7Message(withName: "wired.board.delete_board", spec: spec)
            m.addParameter(field: "wired.board.board", value: path)
            if let response = try await send(m), response.name == "wired.error" {
                throw WiredError(message: response)
            }
        }
    }

    func renameBoard(path: String, newPath: String) async throws {
        try await withBoardNetworkActivity {
            let m = P7Message(withName: "wired.board.rename_board", spec: spec)
            m.addParameter(field: "wired.board.board", value: path)
            m.addParameter(field: "wired.board.new_board", value: newPath)
            if let response = try await send(m), response.name == "wired.error" {
                throw WiredError(message: response)
            }
        }
    }

    func moveBoard(path: String, newPath: String) async throws {
        try await withBoardNetworkActivity {
            let m = P7Message(withName: "wired.board.move_board", spec: spec)
            m.addParameter(field: "wired.board.board", value: path)
            m.addParameter(field: "wired.board.new_board", value: newPath)
            if let response = try await send(m), response.name == "wired.error" {
                throw WiredError(message: response)
            }
        }
    }

    func editThread(
        uuid: String,
        subject: String,
        text: String,
        attachments: [ComposerAttachmentItem] = [],
        sendAttachmentIDs: Bool = true
    ) async throws {
        try await withBoardNetworkActivity {
            let payload = try await resolvedBoardMessagePayload(
                text: text,
                attachments: attachments,
                uploadScope: .thread(uuid)
            )
            let m = P7Message(withName: "wired.board.edit_thread", spec: spec)
            m.addParameter(field: "wired.board.thread", value: uuid)
            m.addParameter(field: "wired.board.subject", value: subject)
            m.addParameter(field: "wired.board.text", value: payload.text)
            if sendAttachmentIDs && !payload.attachmentIDs.isEmpty {
                m.addParameter(field: "wired.attachment.ids", value: payload.attachmentIDs)
            }
            if let response = try await send(m), response.name == "wired.error" {
                throw WiredError(message: response)
            }
        }
    }

    func moveThread(uuid: String, newBoardPath: String) async throws {
        try await withBoardNetworkActivity {
            let m = P7Message(withName: "wired.board.move_thread", spec: spec)
            m.addParameter(field: "wired.board.thread", value: uuid)
            m.addParameter(field: "wired.board.new_board", value: newBoardPath)
            if let response = try await send(m), response.name == "wired.error" {
                throw WiredError(message: response)
            }
        }
    }

    func editPost(
        uuid: String,
        subject: String,
        text: String,
        attachments: [ComposerAttachmentItem] = [],
        sendAttachmentIDs: Bool = true
    ) async throws {
        try await withBoardNetworkActivity {
            let payload = try await resolvedBoardMessagePayload(
                text: text,
                attachments: attachments,
                uploadScope: .post(uuid)
            )
            let m = P7Message(withName: "wired.board.edit_post", spec: spec)
            m.addParameter(field: "wired.board.post", value: uuid)
            m.addParameter(field: "wired.board.subject", value: subject)
            m.addParameter(field: "wired.board.text", value: payload.text)
            if sendAttachmentIDs && !payload.attachmentIDs.isEmpty {
                m.addParameter(field: "wired.attachment.ids", value: payload.attachmentIDs)
            }
            if let response = try await send(m), response.name == "wired.error" {
                throw WiredError(message: response)
            }
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

    // MARK: - Reactions

    /// Fetches the reaction summaries for a post (or a thread body when `post.isThreadBody == true`)
    /// and updates the post's `reactions` and `reactionsLoaded` properties on the main actor.
    func getReactions(forPost post: BoardPost) async throws {
        let connection = try requireAsyncConnection()

        let m = P7Message(withName: "wired.board.get_reactions", spec: spec)
        m.addParameter(field: "wired.board.thread", value: post.threadUUID)
        if !post.isThreadBody {
            m.addParameter(field: "wired.board.post", value: post.uuid)
        }

        var summaries: [BoardReactionSummary] = []
        for try await response in try connection.sendAndWaitMany(m) {
            guard response.name == "wired.board.reaction_list",
                  let emoji = response.string(forField: "wired.board.reaction.emoji"),
                  let count  = response.uint32(forField: "wired.board.reaction.count"),
                  let isOwn  = response.bool(forField: "wired.board.reaction.is_own")
            else { continue }
            let nicksStr = response.string(forField: "wired.board.reaction.nicks") ?? ""
            let nicks = nicksStr.isEmpty ? [] : nicksStr.components(separatedBy: "|")
            summaries.append(BoardReactionSummary(emoji: emoji, count: Int(count), isOwn: isOwn, nicks: nicks))
        }

        post.reactions = summaries
        post.reactionsLoaded = true

        // Mirror emoji list to the parent thread for the thread-list preview.
        if post.isThreadBody {
            thread(uuid: post.threadUUID)?.topReactionEmojis = summaries.map(\.emoji)
        }

        // Apply any reaction animations that arrived while the thread was closed.
        let innerKey = post.isThreadBody ? "body" : post.uuid
        if let pendingEmojis = pendingReactionAnimations[post.threadUUID]?[innerKey],
           !pendingEmojis.isEmpty {
            pendingReactionAnimations[post.threadUUID]?.removeValue(forKey: innerKey)
            // Only animate emojis that are actually present in the loaded reactions.
            let toAnimate = pendingEmojis.filter { e in summaries.contains { $0.emoji == e } }
            guard !toAnimate.isEmpty else { return }
            let capturedPost = post
            Task { @MainActor in
                // Wait for the thread view to finish rendering before shaking.
                try? await Task.sleep(for: .milliseconds(600))
                capturedPost.newReactionEmojis = toAnimate
                try? await Task.sleep(for: .milliseconds(800))
                capturedPost.newReactionEmojis = []
            }
        }
    }

    /// Sends an `add_reaction` toggle request. The server will reply with `reaction_added`
    /// or `reaction_removed` broadcast which `ConnectionController` handles to update state.
    func toggleReaction(emoji: String, forPost post: BoardPost) async throws {
        let m = P7Message(withName: "wired.board.add_reaction", spec: spec)
        m.addParameter(field: "wired.board.thread", value: post.threadUUID)
        if !post.isThreadBody {
            m.addParameter(field: "wired.board.post", value: post.uuid)
        }
        m.addParameter(field: "wired.board.reaction.emoji", value: emoji)
        if let response = try await send(m), response.name == "wired.error" {
            throw WiredError(message: response)
        }
        // Refresh so isOwn is accurate. Keep reactionsLoaded = true so applyReactionBroadcast
        // (which fires concurrently) can still update other clients' counts.
        try? await getReactions(forPost: post)
    }

    /// Called from `ConnectionController` when a `reaction_added` or `reaction_removed`
    /// broadcast arrives. Finds the matching post and updates its reaction summaries in-place.
    func applyReactionBroadcast(threadUUID: String, postUUID: String?,
                                emoji: String, count: Int, added: Bool, nick: String?) {
        // Locate the target post (thread body or reply).
        let target: BoardPost?
        if let postUUID {
            target = thread(uuid: threadUUID)?.posts.first { $0.uuid == postUUID }
        } else {
            target = thread(uuid: threadUUID)?.posts.first { $0.isThreadBody }
        }

        // Always keep the thread-list emoji preview in sync, regardless of whether
        // the full reaction detail has been lazily loaded for this thread.
        if postUUID == nil, let t = thread(uuid: threadUUID) {
            if count == 0 {
                t.topReactionEmojis.removeAll { $0 == emoji }
            } else if added, !t.topReactionEmojis.contains(emoji) {
                t.topReactionEmojis.append(emoji)
            }
        }

        // Unread-reaction badge: count incoming reactions from other users.
        let reactorNick = nick
        let isOwnReaction = reactorNick == nil || reactorNick == currentNick
        if added, !isOwnReaction, let t = thread(uuid: threadUUID) {
            // Only increment when the thread is not the one currently being viewed.
            if threadUUID != selectedThreadUUID {
                t.unreadReactionCount += 1
                connectionController.updateNotificationsBadge()
            }
        }
        if !added, !isOwnReaction, let t = thread(uuid: threadUUID), t.unreadReactionCount > 0 {
            t.unreadReactionCount -= 1
            connectionController.updateNotificationsBadge()
        }

        // If the post/reactions aren't loaded yet, store the emoji for deferred animation.
        if added, !isOwnReaction {
            if target == nil || !target!.reactionsLoaded {
                let innerKey = postUUID ?? "body"
                pendingReactionAnimations[threadUUID, default: [:]][innerKey, default: []].insert(emoji)
            }
        }

        // Post-level detail update only makes sense when reactions are already loaded.
        guard let post = target, post.reactionsLoaded else { return }

        if count == 0 {
            post.reactions.removeAll { $0.emoji == emoji }
        } else if let idx = post.reactions.firstIndex(where: { $0.emoji == emoji }) {
            // Update existing summary — preserve isOwn; append nick on addition.
            var updatedNicks = post.reactions[idx].nicks
            if added, let nick, !updatedNicks.contains(nick) {
                updatedNicks.append(nick)
            }
            // On removal we can't know which nick left without a full refresh,
            // so nicks stay slightly stale until the next getReactions call.
            post.reactions[idx] = BoardReactionSummary(
                emoji: emoji,
                count: count,
                isOwn: post.reactions[idx].isOwn,
                nicks: updatedNicks
            )
        } else if added {
            post.reactions.append(BoardReactionSummary(
                emoji: emoji, count: count, isOwn: false,
                nicks: nick.map { [$0] } ?? []
            ))
        }

        // Trigger shake animation on the chip for incoming reactions from other users.
        if added, !isOwnReaction {
            post.newReactionEmojis.insert(emoji)
            let capturedPost = post
            let capturedEmoji = emoji
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(800))
                capturedPost.newReactionEmojis.remove(capturedEmoji)
            }
        }
    }

    private func requireAsyncConnection() throws -> AsyncConnection {
        guard let connection = connection as? AsyncConnection else {
            throw AsyncConnectionError.notConnected
        }

        return connection
    }

    private func normalizedRequestError(_ error: Error) -> Error {
        if let asyncError = error as? AsyncConnectionError,
           case let .serverError(message) = asyncError {
            return WiredError(message: message)
        }

        return error
    }
}
