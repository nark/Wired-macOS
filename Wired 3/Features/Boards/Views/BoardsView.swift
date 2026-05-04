//
//  BoardsView.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 01/03/2026.
//  Copyright © 2026 Read-Write. All rights reserved.
//

import SwiftUI
import CoreTransferable
#if os(macOS)
import AppKit
public typealias BoardsPlatformImage = NSImage
#elseif canImport(UIKit)
import UIKit
public typealias BoardsPlatformImage = UIImage
#endif


private struct FlattenedBoardRow: Identifiable {
    let board: Board
    let depth: Int
    let boardPath: String
    let parentPath: String?

    var id: String { boardPath }
}

private struct BoardSearchSelectionSnapshot {
    let boardPath: String?
    let smartBoardID: String?
    let threadUUID: String?
}

// MARK: - BoardsView

struct BoardsView: View {
    @Environment(ConnectionRuntime.self) private var runtime
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("boardsThreadSortMode") private var legacyThreadSortModeRaw: String = "lastActivity"
    @AppStorage("boardsThreadSortCriterion") private var threadSortCriterionRaw: String = ThreadSortCriterion.lastReplyDate.rawValue
    @AppStorage("boardsThreadSortAscending") private var threadSortAscending: Bool = false
    @AppStorage("boardsSmartBoardsJSON") private var smartBoardsJSON: String = "[]"

    @State private var selectedBoardPath: String?
    @State private var selectedSmartBoardID: String?
    @State private var selectedThreadUUID: String?
    @State private var showNewThread   = false
    @State private var showNewBoard    = false
    @State private var showNewSmartBoard = false
    @State private var showReply       = false
    @State private var boardToRename: Board?
    @State private var boardToMove: Board?
    @State private var boardToDelete: Board?
    @State private var boardToEditPermissions: Board?
    @State private var smartBoards: [SmartBoardDefinition] = []
    @State private var smartBoardToEdit: SmartBoardDefinition?
    @State private var smartBoardToDelete: SmartBoardDefinition?
    @State private var threadToEdit: BoardThread?
    @State private var threadToMove: BoardThread?
    @State private var threadToDelete: BoardThread?
    @State private var expandedBoardPaths: Set<String> = []
    @State private var hasLoadedBoardExpansionState = false
    @State private var boardDropTargetPath: String?
    @State private var isRootBoardDropTargeted = false
    @State private var smartBoardDropTargetID: String?
    @State private var searchText: String = ""
    @State private var selectedBoardSearchResultID: String?
    @State private var boardSearchSelectionSnapshot: BoardSearchSelectionSnapshot?
    @State private var shouldRestoreBoardSearchSelection = true

    private var boardListSelection: Binding<String?> {
        Binding(
            get: {
                if let smartID = selectedSmartBoardID {
                    return "smart:\(smartID)"
                }
                return selectedBoardPath
            },
            set: { value in
                if let value, value.hasPrefix("smart:") {
                    selectedSmartBoardID = String(value.dropFirst("smart:".count))
                    selectedBoardPath = nil
                } else {
                    selectedSmartBoardID = nil
                    selectedBoardPath = value
                }
            }
        )
    }

    private var selectedBoard: Board? {
        guard let selectedBoardPath else { return nil }
        return runtime.board(path: selectedBoardPath)
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearchMode: Bool {
        trimmedSearchText.count >= 3
    }

    private var boardSearchTaskID: String {
        trimmedSearchText
    }

    private var boardExpansionStorageKey: String {
        "boards.expandedPaths.\(runtime.id.uuidString)"
    }

    private var selectedSmartBoard: SmartBoardDefinition? {
        guard let selectedSmartBoardID else { return nil }
        return smartBoards.first(where: { $0.id == selectedSmartBoardID })
    }

    private func allBoardsFlat() -> [Board] {
        var result: [Board] = []

        func walk(_ boards: [Board]) {
            for board in boards {
                result.append(board)
                if let children = board.children {
                    walk(children)
                }
            }
        }

        walk(runtime.boards)
        return result
    }

    private var allBoardPathsSignature: String {
        allBoardsFlat().map(\.path).sorted().joined(separator: "|")
    }

    private func boardHasChildren(_ board: Board) -> Bool {
        !(board.children?.isEmpty ?? true)
    }

    private func isBoardExpanded(_ board: Board) -> Bool {
        expandedBoardPaths.contains(board.path)
    }

    private func toggleBoardExpanded(_ board: Board) {
        guard boardHasChildren(board) else { return }
        if expandedBoardPaths.contains(board.path) {
            expandedBoardPaths.remove(board.path)
        } else {
            expandedBoardPaths.insert(board.path)
        }
    }

    private func restoreSelectionFromRuntime() {
        let boardPath    = runtime.selectedBoardPath
        let threadUUID   = runtime.selectedThreadUUID
        let smartBoardID = runtime.selectedSmartBoardID
        guard boardPath != nil || threadUUID != nil || smartBoardID != nil else { return }

        if let smartBoardID {
            // Smart board: set directly — its onChange does not clear threadUUID
            selectedSmartBoardID = smartBoardID
        } else {
            selectedBoardPath = boardPath
        }

        // onChange(of: selectedBoardPath) clears selectedThreadUUID and
        // runtime.selectedThreadUUID, so we restore the thread in the next
        // run-loop turn, after those handlers have fired.
        if let threadUUID {
            Task { @MainActor in
                self.selectedThreadUUID = threadUUID
                runtime.selectedThreadUUID = threadUUID
            }
        }
    }

    private func restoreBoardExpansionState() {
        let defaults = UserDefaults.standard
        let expandablePaths = Set(allBoardsFlat().filter(boardHasChildren).map(\.path))

        let decoded: [String]?
        if let stored = defaults.array(forKey: boardExpansionStorageKey) as? [String] {
            decoded = stored
        } else if let data = defaults.data(forKey: boardExpansionStorageKey) {
            decoded = try? JSONDecoder().decode([String].self, from: data)
        } else {
            decoded = nil
        }

        if let decoded {
            expandedBoardPaths = Set(decoded).intersection(expandablePaths)
        } else {
            expandedBoardPaths = Set(runtime.boards.filter(boardHasChildren).map(\.path))
        }
        hasLoadedBoardExpansionState = true
    }

    private func persistBoardExpansionState() {
        guard hasLoadedBoardExpansionState else { return }
        UserDefaults.standard.set(Array(expandedBoardPaths).sorted(), forKey: boardExpansionStorageKey)
    }

    private func applyPendingBoardPathRemaps() {
        guard !runtime.pendingBoardPathRemaps.isEmpty else { return }

        var updated = expandedBoardPaths
        for remap in runtime.pendingBoardPathRemaps {
            if updated.remove(remap.from) != nil {
                updated.insert(remap.to)
            }
        }
        expandedBoardPaths = updated

        if let selectedBoardPath {
            for remap in runtime.pendingBoardPathRemaps {
                if selectedBoardPath == remap.from {
                    self.selectedBoardPath = remap.to
                    break
                }
            }
        }

        runtime.pendingBoardPathRemaps = []
    }

    private func sanitizeExpandedBoardPathsAfterBoardsUpdate() {
        // Skip sanitization while the tree is being rebuilt (e.g. after resetBoards + getBoards).
        // Intermediate states would incorrectly wipe the expansion set.
        guard runtime.boardsLoaded else { return }

        let expandablePaths = Set(allBoardsFlat().filter(boardHasChildren).map(\.path))
        let sanitized = expandedBoardPaths.intersection(expandablePaths)

        if hasLoadedBoardExpansionState {
            if sanitized != expandedBoardPaths {
                expandedBoardPaths = sanitized
            }
            return
        }

        if expandedBoardPaths.isEmpty {
            expandedBoardPaths = Set(runtime.boards.filter(boardHasChildren).map(\.path))
        } else if sanitized != expandedBoardPaths {
            expandedBoardPaths = sanitized
        }
    }

    private var visibleBoardRows: [FlattenedBoardRow] {
        func sortedBoards(_ boards: [Board]) -> [Board] {
            boards.sorted { $0.path < $1.path }
        }

        func flatten(_ boards: [Board], depth: Int, parentPath: String?) -> [FlattenedBoardRow] {
            var rows: [FlattenedBoardRow] = []
            let orderedBoards = sortedBoards(boards)
            for board in orderedBoards {
                rows.append(FlattenedBoardRow(
                    board: board,
                    depth: depth,
                    boardPath: board.path,
                    parentPath: parentPath
                ))
                if isBoardExpanded(board), let children = board.children {
                    rows.append(contentsOf: flatten(children, depth: depth + 1, parentPath: board.path))
                }
            }
            return rows
        }

        return flatten(runtime.boards, depth: 0, parentPath: nil)
    }

    private func canDropBoardAtRoot(_ sourceBoardPath: String) -> Bool {
        guard runtime.hasPrivilege("wired.account.board.move_boards") else { return false }
        return sourceBoardPath.contains("/")
    }

    private func handleBoardDropAtRoot(_ sourceBoardPath: String) -> Bool {
        guard canDropBoardAtRoot(sourceBoardPath) else { return false }

        let boardName = (sourceBoardPath as NSString).lastPathComponent
        let newPath = boardName
        guard newPath != sourceBoardPath else { return false }

        // Server is flat: each board path must be renamed individually.
        let allPaths = runtime.boardsByPath.keys
            .filter { $0 == sourceBoardPath || $0.hasPrefix(sourceBoardPath + "/") }
            .sorted()

        Task {
            do {
                for path in allPaths {
                    let suffix = String(path.dropFirst(sourceBoardPath.count))
                    try await runtime.moveBoard(path: path, newPath: newPath + suffix)
                }
            } catch {
                await MainActor.run {
                    runtime.lastError = error
                }
            }
        }
        return true
    }

    private func remapPath(_ path: String, from oldPath: String, to newPath: String) -> String {
        if path == oldPath {
            return newPath
        }
        let prefix = oldPath + "/"
        guard path.hasPrefix(prefix) else { return path }
        let suffix = String(path.dropFirst(prefix.count))
        return newPath + "/" + suffix
    }

    private func preserveUIStateForMovedBoard(oldPath: String, newPath: String, destinationParentPath: String?) {
        var remappedExpandedPaths: Set<String> = []
        for path in expandedBoardPaths {
            remappedExpandedPaths.insert(remapPath(path, from: oldPath, to: newPath))
        }
        if let destinationParentPath {
            remappedExpandedPaths.insert(destinationParentPath)
        }
        expandedBoardPaths = remappedExpandedPaths

        if let selectedBoardPath {
            self.selectedBoardPath = remapPath(selectedBoardPath, from: oldPath, to: newPath)
        }
    }

    private func boardsForSmartBoard(_ smartBoard: SmartBoardDefinition) -> [Board] {
        let allBoards = allBoardsFlat()
        let scope = smartBoard.discussionPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !scope.isEmpty else { return allBoards }
        return allBoards.filter { $0.path == scope || $0.path.hasPrefix(scope + "/") }
    }

    private func filteredThreads(for smartBoard: SmartBoardDefinition) -> [BoardThread] {
        let subjectFilter = smartBoard.subjectContains.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let replyFilter = smartBoard.replyContains.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let nickFilter = smartBoard.nickContains.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let threads = boardsForSmartBoard(smartBoard).flatMap { $0.threads }

        return threads.filter { thread in
            if smartBoard.unreadOnly && thread.unreadPostsCount + thread.unreadReactionCount <= 0 {
                return false
            }

            if !subjectFilter.isEmpty && !thread.subject.lowercased().contains(subjectFilter) {
                return false
            }

            if !nickFilter.isEmpty {
                let threadNickMatch = thread.nick.lowercased().contains(nickFilter)
                let postNickMatch = thread.posts.contains { $0.nick.lowercased().contains(nickFilter) }
                if !threadNickMatch && !postNickMatch {
                    return false
                }
            }

            if !replyFilter.isEmpty {
                let replyMatch = thread.posts.contains { $0.text.lowercased().contains(replyFilter) }
                if !replyMatch {
                    return false
                }
            }

            return true
        }
    }

    private var visibleThreads: [BoardThread] {
        if let smartBoard = selectedSmartBoard {
            return sortedThreads(filteredThreads(for: smartBoard))
        }
        if let board = selectedBoard {
            return sortedThreads(board.threads)
        }
        return []
    }

    private var selectedThread: BoardThread? {
        guard let selectedThreadUUID else { return nil }
        return visibleThreads.first(where: { $0.uuid == selectedThreadUUID }) ?? runtime.thread(uuid: selectedThreadUUID)
    }

    private var selectedBoardSearchResult: BoardSearchResult? {
        guard let selectedBoardSearchResultID else { return nil }
        return runtime.boardSearchResults.first(where: { $0.id == selectedBoardSearchResultID })
    }

    private func thread(for searchResult: BoardSearchResult) -> BoardThread? {
        runtime.thread(boardPath: searchResult.boardPath, uuid: searchResult.threadUUID)
        ?? runtime.thread(uuid: searchResult.threadUUID)
    }

    private func threadsForBoardListAction(_ board: Board) -> [BoardThread] {
        allBoardsFlat()
            .filter { $0.path == board.path || $0.path.hasPrefix(board.path + "/") }
            .flatMap(\.threads)
    }

    private func canEditThread(_ thread: BoardThread) -> Bool {
        runtime.hasPrivilege("wired.account.board.edit_all_threads_and_posts")
        || (runtime.hasPrivilege("wired.account.board.edit_own_threads_and_posts") && thread.isOwn)
    }

    private func canDeleteThread(_ thread: BoardThread) -> Bool {
        runtime.hasPrivilege("wired.account.board.delete_all_threads_and_posts")
        || (runtime.hasPrivilege("wired.account.board.delete_own_threads_and_posts") && thread.isOwn)
    }

    private func threadReadStateLabel(for thread: BoardThread) -> String {
        thread.unreadPostsCount + thread.unreadReactionCount > 0
            ? NSLocalizedString("Mark as Read", comment: "")
            : NSLocalizedString("Mark as Unread", comment: "")
    }

    private func toggleThreadReadState(_ thread: BoardThread) {
        if thread.unreadPostsCount + thread.unreadReactionCount > 0 {
            runtime.markThreadAsRead(thread)
        } else {
            runtime.markThreadAsUnread(thread)
        }
    }

    private func canReply(to thread: BoardThread) -> Bool {
        if selectedSmartBoard != nil && !isSearchMode {
            return false
        }
        return runtime.board(path: thread.boardPath)?.writable ?? false
    }

    private func openReplyForThread(_ thread: BoardThread) {
        guard canReply(to: thread) else { return }
        selectedThreadUUID = thread.uuid
        showReply = true
    }

    private func threadFromSelection(_ selection: Set<String>) -> BoardThread? {
        guard selection.count == 1, let uuid = selection.first else { return nil }
        return visibleThreads.first(where: { $0.uuid == uuid }) ?? runtime.thread(uuid: uuid)
    }

    private func canDropThread(_ threadUUID: String, into destinationBoard: Board) -> Bool {
        guard runtime.hasPrivilege("wired.account.board.move_threads") else { return false }
        guard let sourceThread = runtime.thread(uuid: threadUUID) else { return false }
        guard destinationBoard.writable else { return false }
        guard sourceThread.boardPath != destinationBoard.path else { return false }
        return true
    }

    private func handleThreadDrop(_ threadUUID: String, into destinationBoard: Board) -> Bool {
        guard canDropThread(threadUUID, into: destinationBoard) else { return false }

        Task {
            do {
                try await runtime.moveThread(uuid: threadUUID, newBoardPath: destinationBoard.path)
            } catch {
                await MainActor.run {
                    runtime.lastError = error
                }
            }
        }
        return true
    }

    private func canDropBoard(_ sourceBoardPath: String, into destinationBoard: Board) -> Bool {
        guard runtime.hasPrivilege("wired.account.board.move_boards") else { return false }
        guard sourceBoardPath != destinationBoard.path else { return false }
        guard destinationBoard.path.hasPrefix(sourceBoardPath + "/") == false else { return false }
        return true
    }

    private func handleBoardDrop(_ sourceBoardPath: String, into destinationBoard: Board) -> Bool {
        guard canDropBoard(sourceBoardPath, into: destinationBoard) else { return false }

        let boardName = (sourceBoardPath as NSString).lastPathComponent
        let newPath = destinationBoard.path + "/" + boardName
        guard newPath != sourceBoardPath else { return false }

        // Pre-expand destination so the moved board will be visible
        expandedBoardPaths.insert(destinationBoard.path)

        // Server is flat: each board path must be renamed individually.
        // Parent first so the client-side moveBoardInTree handles the subtree
        // in one shot; subsequent server notifications are no-ops.
        let allPaths = runtime.boardsByPath.keys
            .filter { $0 == sourceBoardPath || $0.hasPrefix(sourceBoardPath + "/") }
            .sorted()

        Task {
            do {
                for path in allPaths {
                    let suffix = String(path.dropFirst(sourceBoardPath.count))
                    try await runtime.moveBoard(path: path, newPath: newPath + suffix)
                }
            } catch {
                await MainActor.run {
                    runtime.lastError = error
                }
            }
        }
        return true
    }

    private var currentThreadSortCriterion: ThreadSortCriterion {
        if let criterion = ThreadSortCriterion(rawValue: threadSortCriterionRaw) {
            return criterion
        }
        // Migration from old 2-mode setting.
        switch legacyThreadSortModeRaw {
        case "creationDate":
            return .subjectDate
        default:
            return .lastReplyDate
        }
    }

    private func sortedThreads(_ threads: [BoardThread]) -> [BoardThread] {
        threads.sorted { lhs, rhs in
            let primary: ComparisonResult = {
                switch currentThreadSortCriterion {
                case .unread:
                    let lhsUnread = lhs.unreadPostsCount + lhs.unreadReactionCount
                    let rhsUnread = rhs.unreadPostsCount + rhs.unreadReactionCount
                    if lhsUnread < rhsUnread { return .orderedAscending }
                    if lhsUnread > rhsUnread { return .orderedDescending }
                    return .orderedSame
                case .subject:
                    return lhs.subject.localizedCaseInsensitiveCompare(rhs.subject)
                case .nick:
                    return lhs.nick.localizedCaseInsensitiveCompare(rhs.nick)
                case .replies:
                    if lhs.replies < rhs.replies { return .orderedAscending }
                    if lhs.replies > rhs.replies { return .orderedDescending }
                    return .orderedSame
                case .subjectDate:
                    if lhs.postDate < rhs.postDate { return .orderedAscending }
                    if lhs.postDate > rhs.postDate { return .orderedDescending }
                    return .orderedSame
                case .lastReplyDate:
                    let lhsDate = lhs.lastReplyDate ?? lhs.postDate
                    let rhsDate = rhs.lastReplyDate ?? rhs.postDate
                    if lhsDate < rhsDate { return .orderedAscending }
                    if lhsDate > rhsDate { return .orderedDescending }
                    return .orderedSame
                }
            }()

            if primary != .orderedSame {
                return threadSortAscending ? (primary == .orderedAscending) : (primary == .orderedDescending)
            }

            if lhs.subject != rhs.subject {
                return lhs.subject.localizedCaseInsensitiveCompare(rhs.subject) == .orderedAscending
            }
            return lhs.uuid < rhs.uuid
        }
    }

    private func sortedThreads(for board: Board) -> [BoardThread] {
        sortedThreads(board.threads)
    }

    private var threadSortMenu: some View {
        ThreadSortMenuView(
            criterion: Binding(
                get: { currentThreadSortCriterion },
                set: { threadSortCriterionRaw = $0.rawValue }
            ),
            ascending: $threadSortAscending
        )
    }

    var body: some View {
        layout
        .task {
            loadSmartBoards()
        }
        .task(id: boardSearchTaskID) {
            guard isSearchMode else { return }

            beginBoardSearchSessionIfNeeded()

            do {
                try await Task.sleep(for: .milliseconds(250))
                try Task.checkCancellation()
                try await runtime.searchBoards(query: trimmedSearchText, scopeBoardPath: nil)
            } catch {
                if error is CancellationError {
                    return
                }
                runtime.lastError = error
            }
        }
        .onChange(of: isSearchMode) { _, isActive in
            if isActive {
                beginBoardSearchSessionIfNeeded()
            } else {
                endBoardSearchSession()
            }
        }
        .onChange(of: selectedSmartBoardID) { _, smartID in
            guard smartID != nil else { return }
            commitBoardSearchSelectionIfNeeded()
            selectedThreadUUID = nil
            runtime.selectedBoardPath = nil
            runtime.selectedThreadUUID = nil
            runtime.selectedSmartBoardID = smartID
            if let smartBoard = selectedSmartBoard {
                Task { await preloadSmartBoardData(for: smartBoard) }
            }
        }
        .onChange(of: runtime.allBoardThreadsLoaded) { _, loaded in
            guard loaded, let smartBoard = selectedSmartBoard else { return }
            Task { await preloadSmartBoardData(for: smartBoard) }
        }
        .onAppear {
            restoreSelectionFromRuntime()
        }
    }

    @ViewBuilder
    private var layout: some View {
        #if os(macOS)
        HSplitView {
            boardsList
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
                .searchable(text: $searchText)
                .wiredSearchFieldFocus()

            HSplitView {
                threadsList
                    .frame(minWidth: 280, idealWidth: 360, maxWidth: 520)

                postsDetail
                    .frame(minWidth: 320, idealWidth: 520, maxWidth: .infinity)
                    .layoutPriority(1)
            }
        }
        #else
        if horizontalSizeClass == .compact {
            NavigationStack {
                compactContent
            }
        } else {
            NavigationSplitView {
                boardsList
            } content: {
                threadsList
            } detail: {
                postsDetail
            }
        }
        #endif
    }

    #if os(iOS)
    @ViewBuilder
    private var compactContent: some View {
        if selectedBoardPath == nil && selectedSmartBoardID == nil {
            boardsList
                .navigationTitle("Boards")
        } else if selectedThreadUUID == nil {
            threadsList
                .navigationTitle(selectedBoard?.name ?? selectedSmartBoard?.name ?? NSLocalizedString("Threads", comment: ""))
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Boards") {
                            selectedBoardPath = nil
                            selectedSmartBoardID = nil
                            selectedThreadUUID = nil
                        }
                    }
                }
        } else {
            postsDetail
                .navigationTitle(selectedThread?.subject ?? NSLocalizedString("Posts", comment: ""))
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Threads") {
                            selectedThreadUUID = nil
                        }
                    }
                }
        }
    }
    #endif

    private func loadSmartBoards() {
        guard let data = smartBoardsJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([SmartBoardDefinition].self, from: data) else {
            smartBoards = []
            return
        }
        smartBoards = decoded
    }

    private func persistSmartBoards() {
        guard let data = try? JSONEncoder().encode(smartBoards),
              let string = String(data: data, encoding: .utf8) else {
            return
        }
        smartBoardsJSON = string
    }

    private func upsertSmartBoard(_ value: SmartBoardDefinition) {
        if let index = smartBoards.firstIndex(where: { $0.id == value.id }) {
            smartBoards[index] = value
        } else {
            smartBoards.append(value)
        }
        persistSmartBoards()
    }

    private func deleteSmartBoard(_ value: SmartBoardDefinition) {
        smartBoards.removeAll { $0.id == value.id }
        if selectedSmartBoardID == value.id {
            selectedSmartBoardID = nil
            selectedThreadUUID = nil
        }
        persistSmartBoards()
    }

    private func preloadSmartBoardData(for smartBoard: SmartBoardDefinition) async {
        let boards = boardsForSmartBoard(smartBoard)
        let needsPosts = !smartBoard.replyContains.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard needsPosts else { return }

        for board in boards {
            for thread in board.threads where !thread.postsLoaded {
                try? await runtime.getPosts(forThread: thread)
            }
        }
    }

    private func beginBoardSearchSessionIfNeeded() {
        guard boardSearchSelectionSnapshot == nil else { return }

        boardSearchSelectionSnapshot = BoardSearchSelectionSnapshot(
            boardPath: selectedBoardPath,
            smartBoardID: selectedSmartBoardID,
            threadUUID: selectedThreadUUID
        )
        shouldRestoreBoardSearchSelection = true
        selectedBoardSearchResultID = nil
    }

    private func commitBoardSearchSelectionIfNeeded() {
        guard boardSearchSelectionSnapshot != nil else { return }
        shouldRestoreBoardSearchSelection = false

        if isSearchMode {
            searchText = ""
        } else {
            endBoardSearchSession()
        }
    }

    private func endBoardSearchSession() {
        runtime.clearBoardSearch()
        selectedBoardSearchResultID = nil
        let snapshot = boardSearchSelectionSnapshot
        boardSearchSelectionSnapshot = nil
        let shouldRestoreSelection = shouldRestoreBoardSearchSelection
        shouldRestoreBoardSearchSelection = true

        guard shouldRestoreSelection, let snapshot else { return }

        selectedSmartBoardID = snapshot.smartBoardID
        selectedBoardPath = snapshot.boardPath
        selectedThreadUUID = snapshot.threadUUID
        runtime.selectedBoardPath = snapshot.boardPath
        runtime.selectedThreadUUID = snapshot.threadUUID
    }

    private func openSearchResult(_ result: BoardSearchResult) {
        Task {
            if runtime.board(path: result.boardPath) == nil {
                await runtime.reloadBoardsAndThreads()
            }

            guard let board = runtime.board(path: result.boardPath) else {
                return
            }

            runtime.selectedBoardPath = board.path

            if !board.threadsLoaded {
                await runtime.ensureThreadsLoaded(for: board)
            }

            guard let thread = runtime.thread(boardPath: board.path, uuid: result.threadUUID)
                ?? runtime.thread(uuid: result.threadUUID) else {
                return
            }

            selectedThreadUUID = thread.uuid
            runtime.selectedThreadUUID = thread.uuid

            if let postUUID = result.postUUID {
                runtime.pendingBoardPostScrollTarget = PendingBoardPostScrollTarget(
                    threadUUID: thread.uuid,
                    postUUID: postUUID
                )
            } else {
                runtime.pendingBoardPostScrollTarget = nil
            }

            if !thread.postsLoaded || result.postUUID != nil {
                try? await runtime.getPosts(forThread: thread)
            }
        }
    }

    private func revealSearchResultInBoard(_ result: BoardSearchResult) {
        Task {
            commitBoardSearchSelectionIfNeeded()
            selectedSmartBoardID = nil

            if runtime.board(path: result.boardPath) == nil {
                await runtime.reloadBoardsAndThreads()
            }

            guard let board = runtime.board(path: result.boardPath) else {
                return
            }

            selectedBoardPath = board.path
            runtime.selectedBoardPath = board.path

            if !board.threadsLoaded {
                await runtime.ensureThreadsLoaded(for: board)
            }

            guard let thread = runtime.thread(boardPath: board.path, uuid: result.threadUUID)
                ?? runtime.thread(uuid: result.threadUUID) else {
                return
            }

            selectedThreadUUID = thread.uuid
            runtime.selectedThreadUUID = thread.uuid

            if let postUUID = result.postUUID {
                runtime.pendingBoardPostScrollTarget = PendingBoardPostScrollTarget(
                    threadUUID: thread.uuid,
                    postUUID: postUUID
                )
            } else {
                runtime.pendingBoardPostScrollTarget = nil
            }

            if !thread.postsLoaded || result.postUUID != nil {
                try? await runtime.getPosts(forThread: thread)
            }
        }
    }

    // MARK: - Boards list

    private var boardsList: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            Group {
                if runtime.boards.isEmpty && !runtime.boardsLoaded && smartBoards.isEmpty {
                    ProgressView("Loading boards…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.boardsWindowBackground)
                } else if runtime.boards.isEmpty && smartBoards.isEmpty {
                    ContentUnavailableView("No Boards", systemImage: "newspaper")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.boardsWindowBackground)
                } else {
                    List(selection: boardListSelection) {
                        Section("SMART BOARDS") {
                            if smartBoards.isEmpty {
                                Text("No Smart Boards")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(smartBoards) { smartBoard in
                                    Label(smartBoard.name, systemImage: "line.3.horizontal.decrease.circle")
                                        .tag("smart:\(smartBoard.id)")
                                        .draggable(smartBoard)
                                        .dropDestination(for: SmartBoardDefinition.self) { items, _ in
                                            guard let source = items.first,
                                                  let fromIndex = smartBoards.firstIndex(where: { $0.id == source.id }),
                                                  let toIndex = smartBoards.firstIndex(where: { $0.id == smartBoard.id }),
                                                  fromIndex != toIndex
                                            else { return false }
                                            withAnimation {
                                                smartBoards.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
                                                persistSmartBoards()
                                            }
                                            return true
                                        } isTargeted: { targeted in
                                            smartBoardDropTargetID = targeted ? smartBoard.id : (smartBoardDropTargetID == smartBoard.id ? nil : smartBoardDropTargetID)
                                        }
                                        .overlay(alignment: .bottom) {
                                            if smartBoardDropTargetID == smartBoard.id {
                                                Rectangle()
                                                    .fill(Color.accentColor)
                                                    .frame(height: 2)
                                                    .offset(y: 1)
                                            }
                                        }
                                        .contextMenu {
                                            let smartBoardThreads = filteredThreads(for: smartBoard)
                                            let canMarkSmartBoardRead = smartBoardThreads.contains { $0.unreadPostsCount > 0 }
                                            let canMarkSmartBoardUnread = smartBoardThreads.contains { $0.unreadPostsCount == 0 }

                                            Button {
                                                runtime.markThreadsAsRead(smartBoardThreads)
                                            } label: {
                                                Label {
                                                    Text("Mark as read")
                                                } icon: {
                                                    Image(systemName: "checkmark.square")
                                                }
                                            }
                                            .disabled(!canMarkSmartBoardRead)

                                            Button {
                                                runtime.markThreadsAsUnread(smartBoardThreads)
                                            } label: {
                                                Label {
                                                    Text("Mark as unread")
                                                } icon: {
                                                    Image(systemName: "square")
                                                }
                                            }
                                            .disabled(!canMarkSmartBoardUnread)

                                            Divider()

                                            Button { smartBoardToEdit = smartBoard } label: {
                                                Label {
                                                    Text("Edit Smart Board")
                                                } icon: {
                                                    Image(systemName: "pencil")
                                                }
                                            }

                                            Divider()

                                            Button(role: .destructive) { smartBoardToDelete = smartBoard } label: {
                                                Label {
                                                    Text("Delete Smart Board")
                                                } icon: {
                                                    Image(systemName: "trash.fill")
                                                }
                                            }
                                        }
                                }
                            }
                        }

                        Section("BOARDS") {
                            ForEach(visibleBoardRows) { row in
                                let board = row.board

                                HStack(spacing: 6) {
                                    if boardHasChildren(board) {
                                        Button {
                                            toggleBoardExpanded(board)
                                        } label: {
                                            Image(systemName: isBoardExpanded(board) ? "chevron.down" : "chevron.right")
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                                .frame(width: 12, height: 12)
                                        }
                                        .buttonStyle(.plain)
                                        .padding(.leading, CGFloat(row.depth) * 10)
                                    } else {
                                        Color.clear
                                            .frame(width: 12, height: 12)
                                            .padding(.leading, CGFloat(row.depth) * 10)
                                    }

                                    BoardRowView(board: board)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .tag(board.path)
                                .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 6))
                                .draggable(BoardDropItem.board(path: board.path))
                                .dropDestination(for: BoardDropItem.self) { items, _ in
                                    guard let item = items.first else { return false }
                                    switch item.kind {
                                    case "board":
                                        return handleBoardDrop(item.identifier, into: board)
                                    case "thread":
                                        return handleThreadDrop(item.identifier, into: board)
                                    default:
                                        return false
                                    }
                                } isTargeted: { isTargeted in
                                    boardDropTargetPath = isTargeted ? board.path : (boardDropTargetPath == board.path ? nil : boardDropTargetPath)
                                }
                                .overlay {
                                    if boardDropTargetPath == board.path {
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.accentColor, lineWidth: 2)
                                            .padding(.vertical, -2)
                                    }
                                }
                                .contextMenu {
                                    let boardThreads = threadsForBoardListAction(board)
                                    let canMarkBoardRead = boardThreads.contains { $0.unreadPostsCount > 0 }
                                    let canMarkBoardUnread = boardThreads.contains { $0.unreadPostsCount == 0 }

                                    Button {
                                        runtime.markThreadsAsRead(boardThreads)
                                    } label: {
                                        Label {
                                            Text("Mark as read")
                                        } icon: {
                                            Image(systemName: "checkmark.square")
                                        }
                                    }
                                    .disabled(!canMarkBoardRead)
                                    
                                    Button {
                                        runtime.markThreadsAsUnread(boardThreads)
                                    } label: {
                                        Label {
                                            Text("Mark as unread")
                                        } icon: {
                                            Image(systemName: "square")
                                        }
                                    }
                                    .disabled(!canMarkBoardUnread)

                                    if runtime.hasPrivilege("wired.account.board.rename_boards") {
                                        Divider()

                                        Button {
                                            boardToRename = board
                                        } label: {
                                            Label {
                                                Text("Rename Board")
                                            } icon: {
                                                Image(systemName: "pencil")
                                            }
                                        }
                                    }

                                    if runtime.hasPrivilege("wired.account.board.set_board_info") {
                                        Button {
                                            boardToEditPermissions = board
                                        } label: {
                                           Label {
                                               Text("Edit Permissions")
                                           } icon: {
                                               Image(systemName: "lock.fill")
                                           }
                                       }
                                    }

                                    if runtime.hasPrivilege("wired.account.board.move_boards") {
                                        Button { boardToMove = board } label: {
                                            Label {
                                                Text("Move Board")
                                            } icon: {
                                                Image(systemName: "arrow.turn.up.right")
                                            }
                                        }
                                    }

                                    if runtime.hasPrivilege("wired.account.board.delete_boards") {
                                        Divider()

                                        Button(role: .destructive) { boardToDelete = board } label: {
                                            Label {
                                                Text("Delete Board")
                                            } icon: {
                                                Image(systemName: "trash.fill")
                                            }
                                        }
                                    }
                                }
                            }

                        }
                        .dropDestination(for: BoardDropItem.self) { items, _ in
                            guard runtime.hasPrivilege("wired.account.board.move_boards") else { return false }
                            guard let item = items.first, item.kind == "board" else { return false }
                            return handleBoardDropAtRoot(item.identifier)
                        } isTargeted: { targeted in
                            isRootBoardDropTargeted = targeted
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .overlay {
                        if isRootBoardDropTargeted {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.accentColor, lineWidth: 2)
                                .padding(4)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()

                HStack(spacing: 0) {
                    Menu {
                        Button {
                            showNewBoard = true
                        } label: {
                            Label("New Board", systemImage: "plus")
                        }
                        .disabled(!runtime.hasPrivilege("wired.account.board.add_boards"))

                        Divider()

                        Button {
                            showNewSmartBoard = true
                        } label: {
                            Label("New Smart Board", systemImage: "line.3.horizontal.decrease.circle")
                        }

                    } label: {
                        Image(systemName: "plus")
                    }
                    .menuStyle(.borderlessButton)
                    .frame(maxWidth: 30)

                    Spacer()

                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 14, height: 14)
                        .opacity(runtime.isPerformingBoardNetworkActivity ? 1 : 0)
                        .animation(.easeInOut(duration: 0.15), value: runtime.isPerformingBoardNetworkActivity)
                        .help("Boards network activity")
                        .padding(.trailing, 8)

                    Button {
                        runtime.markAllBoardThreadsAsRead()
                    } label: {
                        Image(systemName: "checkmark.rectangle.stack.fill")
                    }
                    .help("Mark all as read")
                    .buttonStyle(.plain)
                    .disabled(runtime.totalUnreadBoardPosts == 0)
                }
                .padding(7)
            }
        }
        .sheet(isPresented: $showNewBoard) {
            NewBoardView(parentBoard: selectedBoard)
                .environment(runtime)
        }
        .sheet(isPresented: $showNewSmartBoard) {
            SmartBoardEditorView(
                initialValue: nil,
                discussionOptions: allBoardsFlat().map(\.path)
            ) { value in
                upsertSmartBoard(value)
            }
        }
        .sheet(item: $smartBoardToEdit) { smartBoard in
            SmartBoardEditorView(
                initialValue: smartBoard,
                discussionOptions: allBoardsFlat().map(\.path)
            ) { value in
                upsertSmartBoard(value)
            }
        }
        .sheet(item: $boardToEditPermissions) { board in
            EditBoardPermissionsView(board: board)
                .environment(runtime)
        }
        .sheet(item: $boardToRename) { board in
            BoardPathActionView(
                title: "Rename Board",
                actionLabel: "Rename",
                initialPath: board.path
            ) { newPath in
                try await runtime.renameBoard(path: board.path, newPath: newPath)
            }
            .environment(runtime)
        }
        .sheet(item: $boardToMove) { board in
            BoardPathActionView(
                title: "Move Board",
                actionLabel: "Move",
                initialPath: board.path
            ) { newPath in
                try await runtime.moveBoard(path: board.path, newPath: newPath)
            }
            .environment(runtime)
        }
        .confirmationDialog(
            "Delete board?",
            isPresented: Binding(
                get: { boardToDelete != nil },
                set: { if !$0 { boardToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let board = boardToDelete else { return }
                Task {
                    do {
                        try await runtime.deleteBoard(path: board.path)
                        await MainActor.run {
                            if selectedBoardPath == board.path {
                                selectedBoardPath = nil
                                selectedThreadUUID = nil
                            }
                            boardToDelete = nil
                        }
                    } catch {
                        await MainActor.run {
                            runtime.lastError = error
                            boardToDelete = nil
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                boardToDelete = nil
            }
        } message: {
            Text(boardToDelete?.path ?? "")
        }
        .confirmationDialog(
            "Delete smart board?",
            isPresented: Binding(
                get: { smartBoardToDelete != nil },
                set: { if !$0 { smartBoardToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let smartBoard = smartBoardToDelete {
                    deleteSmartBoard(smartBoard)
                }
                smartBoardToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                smartBoardToDelete = nil
            }
        } message: {
            Text(smartBoardToDelete?.name ?? "")
        }
        .onChange(of: selectedBoardPath) { _, _ in
            if selectedBoardPath != nil {
                commitBoardSearchSelectionIfNeeded()
            }
            runtime.selectedBoardPath = selectedBoardPath
            runtime.selectedThreadUUID = nil
            selectedThreadUUID = nil
            if selectedBoardPath != nil {
                selectedSmartBoardID = nil
                runtime.selectedSmartBoardID = nil
            }
            guard let board = selectedBoard else { return }
            if !board.threadsLoaded {
                Task { await runtime.ensureThreadsLoaded(for: board) }
            }
        }
        .onChange(of: runtime.boardsLoaded) { _, loaded in
            guard loaded else { return }

            guard let selectedBoardPath else {
                selectedThreadUUID = nil
                return
            }

            guard let board = runtime.board(path: selectedBoardPath) else {
                self.selectedBoardPath = nil
                self.selectedThreadUUID = nil
                return
            }

            if !board.threadsLoaded {
                return
            }

            if let selectedThreadUUID, board.threads.contains(where: { $0.uuid == selectedThreadUUID }) == false {
                self.selectedThreadUUID = nil
            }
        }
        .onAppear {
            restoreBoardExpansionState()
        }
        .onChange(of: runtime.id) { _, _ in
            hasLoadedBoardExpansionState = false
            restoreBoardExpansionState()
        }
        .onChange(of: allBoardPathsSignature) { _, _ in
            applyPendingBoardPathRemaps()
            sanitizeExpandedBoardPathsAfterBoardsUpdate()
        }
        .onChange(of: expandedBoardPaths) { _, _ in
            persistBoardExpansionState()
        }
        .onChange(of: runtime.selectedTab) { _, selectedTab in
            guard selectedTab == .boards else { return }
            runtime.markSelectedThreadAsReadIfVisible()
        }
        .onChange(of: selectedBoard?.threadsLoaded) { _, loaded in
            guard loaded == true else { return }
            guard let selectedThreadUUID else { return }

            guard let thread = selectedThread else {
                self.selectedThreadUUID = nil
                return
            }

            if thread.uuid == selectedThreadUUID && !thread.postsLoaded {
                Task { try? await runtime.getPosts(forThread: thread) }
            }
        }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            runtime.markSelectedThreadAsReadIfVisible()
        }
        #endif
        #else
        List(selection: boardListSelection) {
            if !smartBoards.isEmpty {
                Section("SMART BOARDS") {
                    ForEach(smartBoards) { smartBoard in
                        Label(smartBoard.name, systemImage: "line.3.horizontal.decrease.circle")
                            .tag("smart:\(smartBoard.id)")
                    }
                }
            }

            Section("BOARDS") {
                ForEach(visibleBoardRows) { row in
                    let board = row.board
                    HStack(spacing: 6) {
                        if boardHasChildren(board) {
                            Image(systemName: isBoardExpanded(board) ? "chevron.down" : "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 12, height: 12)
                                .padding(.leading, CGFloat(row.depth) * 10)
                                .onTapGesture {
                                    toggleBoardExpanded(board)
                                }
                        } else {
                            Color.clear
                                .frame(width: 12, height: 12)
                                .padding(.leading, CGFloat(row.depth) * 10)
                        }

                        BoardRowView(board: board)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .tag(board.path)
                }
            }
        }
        .listStyle(.inset)
        .onChange(of: boardListSelection.wrappedValue) { _, value in
            guard let value else {
                selectedBoardPath = nil
                selectedSmartBoardID = nil
                selectedThreadUUID = nil
                runtime.selectedBoardPath = nil
                runtime.selectedThreadUUID = nil
                return
            }

            if value.hasPrefix("smart:") {
                let smartID = String(value.dropFirst("smart:".count))
                selectedSmartBoardID = smartID
                selectedBoardPath = nil
                selectedThreadUUID = nil
                runtime.selectedBoardPath = nil
                runtime.selectedThreadUUID = nil
                if let smartBoard = selectedSmartBoard {
                    Task { await preloadSmartBoardData(for: smartBoard) }
                }
                return
            }

            selectedSmartBoardID = nil
            selectedBoardPath = value
            runtime.selectedBoardPath = value
            runtime.selectedThreadUUID = nil
            selectedThreadUUID = nil
            if let board = selectedBoard, !board.threadsLoaded {
                Task { await runtime.ensureThreadsLoaded(for: board) }
            }
        }
        #endif
    }

    // MARK: - Threads list

    @ViewBuilder
    private var boardSearchResultsContent: some View {
        if runtime.isSearchingBoards && runtime.boardSearchResults.isEmpty {
            ProgressView("Searching boards…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.boardsTextBackground)
        } else if runtime.boardSearchResults.isEmpty {
            ContentUnavailableView("No Search Results", systemImage: "magnifyingglass")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.boardsTextBackground)
        } else {
            List(runtime.boardSearchResults, selection: $selectedBoardSearchResultID) { result in
                BoardSearchResultRowView(result: result)
                    .tag(result.id)
                    .listRowInsets(EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 10))
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                    .contentShape(Rectangle())
            }
            .contextMenu(forSelectionType: String.self) { selection in
                if selection.count == 1,
                   let resultID = selection.first,
                   let result = runtime.boardSearchResults.first(where: { $0.id == resultID }),
                   let thread = thread(for: result) {
                    Button {
                        toggleThreadReadState(thread)
                    } label: {
                        Label {
                            Text(threadReadStateLabel(for: thread))
                        } icon: {
                            Image(systemName: "checkmark")
                        }
                    }
                    Divider()
                    
                    if canEditThread(thread) {
                        Button { threadToEdit = thread } label: {
                            Label {
                                Text("Edit Thread")
                            } icon: {
                                Image(systemName: "pencil")
                            }
                        }
                    }
                    
                    if runtime.hasPrivilege("wired.account.board.move_threads") {
                        Button { threadToMove = thread } label: {
                            Label {
                                Text("Move Thread")
                            } icon: {
                                Image(systemName: "arrow.turn.up.right")
                            }
                        }
                    }
                    
                    if canDeleteThread(thread) {
                        Button(role: .destructive) { threadToDelete = thread } label: {
                            Label {
                                Text("Delete Thread")
                            } icon: {
                                Image(systemName: "trash.fill")
                            }
                        }
                    }
                    Divider()
                    Button {
                        selectedBoardSearchResultID = result.id
                        revealSearchResultInBoard(result)
                    } label: {
                        Label {
                            Text("Reveal in Board")
                        } icon: {
                            Image(systemName: "sidebar.leading")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.boardsTextBackground)
            .onChange(of: selectedBoardSearchResultID) { _, resultID in
                guard let resultID,
                      let result = runtime.boardSearchResults.first(where: { $0.id == resultID }) else {
                    return
                }
                openSearchResult(result)
            }
        }
    }

    private var threadsList: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            Group {
                if isSearchMode {
                    boardSearchResultsContent
                } else if selectedSmartBoard != nil {
                    if visibleThreads.isEmpty {
                        ContentUnavailableView("No Matching Threads", systemImage: "line.3.horizontal.decrease.circle")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.boardsTextBackground)
                    } else {
                        List(visibleThreads, selection: $selectedThreadUUID) { thread in
                            ThreadRowView(thread: thread)
                                .tag(thread.uuid)
                                .listRowInsets(EdgeInsets(top: 5, leading: 6, bottom: 5, trailing: 10))
                                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                                .draggable(BoardDropItem.thread(uuid: thread.uuid))
                        }
                        .contextMenu(forSelectionType: String.self) { selection in
                            if let thread = threadFromSelection(selection) {
                                Button {
                                    toggleThreadReadState(thread)
                                } label: {
                                    Label {
                                        Text(threadReadStateLabel(for: thread))
                                    } icon: {
                                        Image(systemName: "checkmark")
                                    }
                                }
                                
                                Divider()
                                if canEditThread(thread) {
                                    Button { threadToEdit = thread } label: {
                                        Label {
                                            Text("Edit Thread")
                                        } icon: {
                                            Image(systemName: "pencil")
                                        }
                                    }
                                }
                                if runtime.hasPrivilege("wired.account.board.move_threads") {
                                    Button { threadToMove = thread } label: {
                                        Label {
                                            Text("Move Thread")
                                        } icon: {
                                            Image(systemName: "arrow.turn.up.right")
                                        }
                                    }
                                }
                                if canDeleteThread(thread) {
                                    Divider()

                                    Button(role: .destructive) { threadToDelete = thread } label: {
                                        Label {
                                            Text("Delete Thread")
                                        } icon: {
                                            Image(systemName: "trash.fill")
                                        }
                                    }
                                }
                            }
                        } primaryAction: { selection in
                            guard let thread = threadFromSelection(selection) else { return }
                            openReplyForThread(thread)
                        }
                        .scrollContentBackground(.hidden)
                        .background(Color.boardsTextBackground)
                    }
                } else if let board = selectedBoard {
                    if !board.threadsLoaded {
                        ProgressView("Loading threads…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.boardsTextBackground)
                    } else if board.threads.isEmpty {
                        ContentUnavailableView("No Threads", systemImage: "text.bubble")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.boardsTextBackground)
                    } else {
                        List(visibleThreads, selection: $selectedThreadUUID) { thread in
                            ThreadRowView(thread: thread)
                                .tag(thread.uuid)
                                .listRowInsets(EdgeInsets(top: 5, leading: 6, bottom: 5, trailing: 10))
                                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                                .draggable(BoardDropItem.thread(uuid: thread.uuid))
                        }
                        .contextMenu(forSelectionType: String.self) { selection in
                            if let thread = threadFromSelection(selection) {
                                Button {
                                    toggleThreadReadState(thread)
                                } label: {
                                    Label {
                                        Text(threadReadStateLabel(for: thread))
                                    } icon: {
                                        Image(systemName: "checkmark")
                                    }
                                }
                                Divider()
                                if canEditThread(thread) {
                                    Button { threadToEdit = thread } label: {
                                        Label {
                                            Text("Edit Thread")
                                        } icon: {
                                            Image(systemName: "pencil")
                                        }
                                    }
                                }
                                if runtime.hasPrivilege("wired.account.board.move_threads") {
                                    Button { threadToMove = thread } label: {
                                        Label {
                                            Text("Move Thread")
                                        } icon: {
                                            Image(systemName: "arrow.turn.up.right")
                                        }
                                    }
                                }
                                if canDeleteThread(thread) {
                                    Button(role: .destructive) { threadToDelete = thread } label: {
                                        Label {
                                            Text("Delete Thread")
                                        } icon: {
                                            Image(systemName: "trash.fill")
                                        }
                                    }
                                }
                            }
                        } primaryAction: { selection in
                            guard let thread = threadFromSelection(selection) else { return }
                            openReplyForThread(thread)
                        }
                        .scrollContentBackground(.hidden)
                        .background(Color.boardsTextBackground)
                    }
                } else {
                    ContentUnavailableView("Select a Board", systemImage: "text.bubble")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.boardsTextBackground)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.boardsTextBackground)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                HStack {
                    Button {
                        showNewThread = true
                    } label: {
                        Label("New", systemImage: "square.and.pencil")
                    }
                    .buttonStyle(.plain)
                    .disabled(isSearchMode || selectedSmartBoard != nil || !(selectedBoard?.writable ?? false))

                    Button {
                        showReply = true
                    } label: {
                        Label("Reply", systemImage: "arrowshape.turn.up.left")
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedThread == nil || (selectedThread.map(canReply(to:)) != true))

                    Spacer()

                    if !isSearchMode {
                        threadSortMenu
                    }
                }
                .padding(.horizontal, 9)
                .padding(.top, 7)
                .padding(.bottom, 8)
                .background(.bar)
            }
        }
        .sheet(isPresented: $showNewThread) {
            if let board = selectedBoard {
                NewThreadView(board: board)
                    .environment(runtime)
            }
        }
        .sheet(isPresented: $showReply) {
            if let thread = selectedThread {
                ReplyView(thread: thread)
                    .environment(runtime)
            }
        }
        .sheet(item: $threadToEdit) { thread in
            EditThreadView(thread: thread)
                .environment(runtime)
        }
        .sheet(item: $threadToMove) { thread in
            MoveThreadView(thread: thread)
                .environment(runtime)
        }
        .confirmationDialog(
            "Delete thread?",
            isPresented: Binding(
                get: { threadToDelete != nil },
                set: { if !$0 { threadToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let thread = threadToDelete else { return }
                Task {
                    do {
                        try await runtime.deleteThread(uuid: thread.uuid)
                        await MainActor.run {
                            if selectedThreadUUID == thread.uuid {
                                selectedThreadUUID = nil
                            }
                            threadToDelete = nil
                        }
                    } catch {
                        await MainActor.run {
                            runtime.lastError = error
                            threadToDelete = nil
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                threadToDelete = nil
            }
        } message: {
            Text(threadToDelete?.subject ?? "")
        }
        .onChange(of: selectedThreadUUID) { _, _ in
            runtime.selectedThreadUUID = selectedThreadUUID
            guard let thread = selectedThread else { return }
            runtime.markSelectedThreadAsReadIfVisible()
            if !thread.postsLoaded {
                Task { try? await runtime.getPosts(forThread: thread) }
            }
        }
        #else
        VStack(spacing: 0) {
            if isSearchMode {
                boardSearchResultsContent
            } else if selectedSmartBoard != nil || selectedBoard != nil {
                if visibleThreads.isEmpty {
                    ContentUnavailableView("No Threads", systemImage: "text.bubble")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(visibleThreads, id: \.uuid, selection: $selectedThreadUUID) { thread in
                        ThreadRowView(thread: thread)
                            .tag(thread.uuid)
                    }
                    .listStyle(.plain)
                }
            } else {
                ContentUnavailableView("Select a Board", systemImage: "newspaper")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.boardsTextBackground)
        .onChange(of: selectedThreadUUID) { _, _ in
            runtime.selectedThreadUUID = selectedThreadUUID
            guard let thread = selectedThread else { return }
            runtime.markSelectedThreadAsReadIfVisible()
            if !thread.postsLoaded {
                Task { try? await runtime.getPosts(forThread: thread) }
            }
        }
        #endif
    }

    // MARK: - Posts detail

    private var postsDetail: some View {
        Group {
            if let thread = selectedThread {
                PostsDetailView(
                    boardPath: thread.boardPath,
                    threadUUID: thread.uuid,
                    highlightQuery: isSearchMode ? trimmedSearchText : nil
                )
                    .environment(runtime)
            } else {
                ContentUnavailableView("Select a Thread", systemImage: "text.alignleft")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.boardsTextBackground)
    }
}
