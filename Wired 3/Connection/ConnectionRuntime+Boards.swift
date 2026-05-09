//
//  ConnectionRuntime+Boards.swift
//  Wired-macOS
//
//  Created by Rafaël Warnault on 19/12/2025.
//  Copyright © 2025 Read-Write. All rights reserved.
//

import SwiftUI
import SwiftData
import WiredSwift

@MainActor
extension ConnectionRuntime {

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
}
