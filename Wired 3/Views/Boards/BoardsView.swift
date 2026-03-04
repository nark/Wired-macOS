//
//  BoardsView.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 01/03/2026.
//  Copyright © 2026 Read-Write. All rights reserved.
//

import SwiftUI
import AppKit
import CoreTransferable

private enum ThreadSortCriterion: String, CaseIterable, Identifiable {
    case unread
    case subject
    case nick
    case replies
    case subjectDate
    case lastReplyDate

    var id: String { rawValue }

    var label: String {
        switch self {
        case .unread: return "Trier par non-lus"
        case .subject: return "Trier par sujets"
        case .nick: return "Trier par pseudo"
        case .replies: return "Trier par reponses"
        case .subjectDate: return "Trier par date du sujet"
        case .lastReplyDate: return "Trier par date de la derniere reponse"
        }
    }
}

private struct SmartBoardDefinition: Identifiable, Codable, Hashable, Transferable {
    var id: String = UUID().uuidString
    var name: String
    var discussionPath: String = ""
    var subjectContains: String = ""
    var replyContains: String = ""
    var nickContains: String = ""
    var unreadOnly: Bool = false

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation { item in
            "smartboard:" + item.id
        } importing: { string in
            guard string.hasPrefix("smartboard:") else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Not a smart board drag"))
            }
            let id = String(string.dropFirst("smartboard:".count))
            return SmartBoardDefinition(id: id, name: "")
        }
    }
}

private struct FlattenedBoardRow: Identifiable {
    let board: Board
    let depth: Int
    let boardPath: String
    let parentPath: String?

    var id: String { boardPath }
}


// MARK: - BoardsView

struct BoardsView: View {
    @Environment(ConnectionRuntime.self) private var runtime
    @AppStorage("boardsThreadSortMode") private var legacyThreadSortModeRaw: String = "lastActivity"
    @AppStorage("boardsThreadSortCriterion") private var threadSortCriterionRaw: String = ThreadSortCriterion.lastReplyDate.rawValue
    @AppStorage("boardsThreadSortAscending") private var threadSortAscending: Bool = false
    @AppStorage("boardsSmartBoardsJSON") private var smartBoardsJSON: String = "[]"

    @State private var selectedBoardPath: String?   = nil
    @State private var selectedSmartBoardID: String? = nil
    @State private var selectedThreadUUID: String?  = nil
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

        Task {
            do {
                try await runtime.moveBoard(path: sourceBoardPath, newPath: newPath)
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
            if smartBoard.unreadOnly && thread.unreadPostsCount <= 0 {
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

    private func canEditThread(_ thread: BoardThread) -> Bool {
        runtime.hasPrivilege("wired.account.board.edit_all_threads_and_posts")
        || (runtime.hasPrivilege("wired.account.board.edit_own_threads_and_posts") && thread.isOwn)
    }

    private func canDeleteThread(_ thread: BoardThread) -> Bool {
        runtime.hasPrivilege("wired.account.board.delete_all_threads_and_posts")
        || (runtime.hasPrivilege("wired.account.board.delete_own_threads_and_posts") && thread.isOwn)
    }

    private func threadReadStateLabel(for thread: BoardThread) -> String {
        thread.unreadPostsCount > 0 ? "Mark as Read" : "Mark as Unread"
    }

    private func toggleThreadReadState(_ thread: BoardThread) {
        if thread.unreadPostsCount > 0 {
            runtime.markThreadAsRead(thread)
        } else {
            runtime.markThreadAsUnread(thread)
        }
    }

    private func canReply(to thread: BoardThread) -> Bool {
        guard selectedSmartBoard == nil else { return false }
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

        Task {
            do {
                try await runtime.moveBoard(path: sourceBoardPath, newPath: newPath)
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
                    let lhsUnread = lhs.unreadPostsCount
                    let rhsUnread = rhs.unreadPostsCount
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
        NavigationSplitView {
            // ── Left column: hierarchical boards list ──────────────────────
            boardsList

        } content: {
            // ── Middle column: threads in selected board ───────────────────
            threadsList

        } detail: {
            // ── Right column: posts in selected thread ─────────────────────
            postsDetail
        }
        .task {
            loadSmartBoards()
        }
        .onChange(of: selectedSmartBoardID) { _, smartID in
            guard smartID != nil else { return }
            selectedThreadUUID = nil
            runtime.selectedBoardPath = nil
            runtime.selectedThreadUUID = nil
            if let smartBoard = selectedSmartBoard {
                Task { await preloadSmartBoardData(for: smartBoard) }
            }
        }
    }

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
        for board in boards where !board.threadsLoaded {
            try? await runtime.getThreads(forBoard: board)
        }

        let needsPosts = !smartBoard.replyContains.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard needsPosts else { return }

        for board in boards {
            for thread in board.threads where !thread.postsLoaded {
                try? await runtime.getPosts(forThread: thread)
            }
        }
    }

    // MARK: - Boards list

    private var boardsList: some View {
        VStack(spacing: 0) {
            Group {
                if runtime.boards.isEmpty && !runtime.boardsLoaded && smartBoards.isEmpty {
                    ProgressView("Loading boards…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(nsColor: .windowBackgroundColor))
                } else if runtime.boards.isEmpty && smartBoards.isEmpty {
                    ContentUnavailableView("No Boards", systemImage: "newspaper")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(nsColor: .windowBackgroundColor))
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
                                            Button("Edit Smart Board") { smartBoardToEdit = smartBoard }
                                            Button("Delete Smart Board", role: .destructive) { smartBoardToDelete = smartBoard }
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
                                        .padding(.leading, row.depth > 0 ? CGFloat(row.depth) * 10 : 0)
                                    } else if row.depth > 0 {
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
                                    if runtime.hasPrivilege("wired.account.board.set_board_info") {
                                        Button("Edit Permissions") { boardToEditPermissions = board }
                                    }
                                    if runtime.hasPrivilege("wired.account.board.rename_boards") {
                                        Button("Rename Board") { boardToRename = board }
                                    }
                                    if runtime.hasPrivilege("wired.account.board.move_boards") {
                                        Button("Move Board") { boardToMove = board }
                                    }
                                    if runtime.hasPrivilege("wired.account.board.delete_boards") {
                                        Button("Delete Board", role: .destructive) { boardToDelete = board }
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
                }
                .padding(9)
                
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
            runtime.selectedBoardPath = selectedBoardPath
            runtime.selectedThreadUUID = nil
            selectedThreadUUID = nil
            if selectedBoardPath != nil {
                selectedSmartBoardID = nil
            }
            guard let board = selectedBoard else { return }
            if !board.threadsLoaded {
                Task { try? await runtime.getThreads(forBoard: board) }
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
                Task { try? await runtime.getThreads(forBoard: board) }
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
    }

    // MARK: - Threads list

    private var threadsList: some View {
        VStack(spacing: 0) {
            Group {
                if selectedSmartBoard != nil {
                    if visibleThreads.isEmpty {
                        ContentUnavailableView("No Matching Threads", systemImage: "line.3.horizontal.decrease.circle")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(nsColor: .textBackgroundColor))
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
                                Button(threadReadStateLabel(for: thread)) {
                                    toggleThreadReadState(thread)
                                }
                                Divider()
                                if canEditThread(thread) {
                                    Button("Edit Thread") { threadToEdit = thread }
                                }
                                if runtime.hasPrivilege("wired.account.board.move_threads") {
                                    Button("Move Thread") { threadToMove = thread }
                                }
                                if canDeleteThread(thread) {
                                    Button("Delete Thread", role: .destructive) { threadToDelete = thread }
                                }
                            }
                        } primaryAction: { selection in
                            guard let thread = threadFromSelection(selection) else { return }
                            openReplyForThread(thread)
                        }
                        .scrollContentBackground(.hidden)
                        .background(Color(nsColor: .textBackgroundColor))
                    }
                } else if let board = selectedBoard {
                    if !board.threadsLoaded {
                        ProgressView("Loading threads…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(nsColor: .textBackgroundColor))
                    } else if board.threads.isEmpty {
                        ContentUnavailableView("No Threads", systemImage: "text.bubble")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(nsColor: .textBackgroundColor))
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
                                Button(threadReadStateLabel(for: thread)) {
                                    toggleThreadReadState(thread)
                                }
                                Divider()
                                if canEditThread(thread) {
                                    Button("Edit Thread") { threadToEdit = thread }
                                }
                                if runtime.hasPrivilege("wired.account.board.move_threads") {
                                    Button("Move Thread") { threadToMove = thread }
                                }
                                if canDeleteThread(thread) {
                                    Button("Delete Thread", role: .destructive) { threadToDelete = thread }
                                }
                            }
                        } primaryAction: { selection in
                            guard let thread = threadFromSelection(selection) else { return }
                            openReplyForThread(thread)
                        }
                        .scrollContentBackground(.hidden)
                        .background(Color(nsColor: .textBackgroundColor))
                    }
                } else {
                    ContentUnavailableView("Select a Board", systemImage: "text.bubble")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(nsColor: .textBackgroundColor))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .textBackgroundColor))
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
                    .disabled(selectedSmartBoard != nil || !(selectedBoard?.writable ?? false))

                    Button {
                        showReply = true
                    } label: {
                        Label("Reply", systemImage: "arrowshape.turn.up.left")
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedThread == nil || selectedSmartBoard != nil || !(selectedBoard?.writable ?? false))
                    
                    Spacer()

                    threadSortMenu
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
            runtime.markThreadAsRead(thread)
            if !thread.postsLoaded {
                Task { try? await runtime.getPosts(forThread: thread) }
            }
        }
    }

    // MARK: - Posts detail

    private var postsDetail: some View {
        Group {
            if let thread = selectedThread {
                PostsDetailView(boardPath: thread.boardPath, threadUUID: thread.uuid)
                    .environment(runtime)
            } else {
                ContentUnavailableView("Select a Thread", systemImage: "text.alignleft")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct ThreadSortMenuView: View {
    @Binding var criterion: ThreadSortCriterion
    @Binding var ascending: Bool

    var body: some View {
        Menu {
            ForEach(ThreadSortCriterion.allCases) { value in
                Toggle(
                    value.label,
                    isOn: Binding(
                        get: { criterion == value },
                        set: { isSelected in
                            if isSelected {
                                criterion = value
                            }
                        }
                    )
                )
            }
            Divider()
            Toggle(
                "Tri ascendant",
                isOn: Binding(
                    get: { ascending },
                    set: { isSelected in
                        if isSelected {
                            ascending = true
                        }
                    }
                )
            )
            Toggle(
                "Tri descendant",
                isOn: Binding(
                    get: { !ascending },
                    set: { isSelected in
                        if isSelected {
                            ascending = false
                        }
                    }
                )
            )
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
        .frame(maxWidth: 30)
        .help("Trier les threads")
        .menuStyle(.borderlessButton)
    }
}

struct MarkdownComposer: View {
    @Binding var text: String
    var minHeight: CGFloat = 180
    var autoFocus: Bool = false
    var onOptionEnter: (() -> Void)? = nil

    @State private var selectedRange: NSRange = NSRange(location: 0, length: 0)

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                button("B", help: "Gras") { wrapSelection(prefix: "**", suffix: "**", placeholder: "bold") }
                button("I", help: "Italique") { wrapSelection(prefix: "*", suffix: "*", placeholder: "italic") }
                button("Code", help: "Code inline") { wrapSelection(prefix: "`", suffix: "`", placeholder: "code") }
                button("Link", help: "Lien") { insertLink() }
                button("Img", help: "Image") { insertImage() }
                button("Quote", help: "Citation") { prefixLines(with: "> ") }
                button("List", help: "Liste") { prefixLines(with: "- ") }
                Spacer(minLength: 0)
            }

            MarkdownTextView(
                text: $text,
                selectedRange: $selectedRange,
                autoFocus: autoFocus,
                onOptionEnter: onOptionEnter
            )
                .frame(minHeight: minHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3))
                        .allowsHitTesting(false)
                )
        }
        .padding(8)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func button(_ title: String, help: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(help)
    }

    private func clampedRange(in value: String) -> NSRange {
        let maxLength = (value as NSString).length
        let location = min(max(0, selectedRange.location), maxLength)
        let length = min(max(0, selectedRange.length), maxLength - location)
        return NSRange(location: location, length: length)
    }

    private func wrapSelection(prefix: String, suffix: String, placeholder: String) {
        let ns = text as NSString
        let range = clampedRange(in: text)
        let selected = range.length > 0 ? ns.substring(with: range) : placeholder
        let replacement = prefix + selected + suffix
        text = ns.replacingCharacters(in: range, with: replacement)

        if range.length > 0 {
            let caret = range.location + (replacement as NSString).length
            selectedRange = NSRange(location: caret, length: 0)
        } else {
            selectedRange = NSRange(location: range.location + (prefix as NSString).length, length: (selected as NSString).length)
        }
    }

    private func insertLink() {
        let ns = text as NSString
        let range = clampedRange(in: text)
        let selected = range.length > 0 ? ns.substring(with: range) : "label"
        let replacement = "[\(selected)](https://)"
        text = ns.replacingCharacters(in: range, with: replacement)

        let linkStart = range.location + ("[\(selected)](" as NSString).length
        selectedRange = NSRange(location: linkStart, length: ("https://" as NSString).length)
    }

    private func insertImage() {
        let ns = text as NSString
        let range = clampedRange(in: text)
        let replacement = "![alt](https://)"
        text = ns.replacingCharacters(in: range, with: replacement)

        let altStart = range.location + ("![" as NSString).length
        selectedRange = NSRange(location: altStart, length: ("alt" as NSString).length)
    }

    private func prefixLines(with prefix: String) {
        let ns = text as NSString
        let range = clampedRange(in: text)
        let lineRange = ns.lineRange(for: range)
        let chunk = ns.substring(with: lineRange)
        let lines = chunk.components(separatedBy: "\n")
        let transformed = lines.map { line -> String in
            if line.isEmpty { return prefix }
            if line.hasPrefix(prefix) { return line }
            return prefix + line
        }.joined(separator: "\n")

        text = ns.replacingCharacters(in: lineRange, with: transformed)
        selectedRange = NSRange(location: lineRange.location, length: (transformed as NSString).length)
    }
}

private struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    var autoFocus: Bool = false
    var onOptionEnter: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, selectedRange: $selectedRange, onOptionEnter: onOptionEnter)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = FocusTextView(frame: .zero, textContainer: textContainer)
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.usesFindBar = true
        textView.allowsUndo = true
        textView.font = .preferredFont(forTextStyle: .body)
        textView.textColor = .textColor
        textView.insertionPointColor = .controlTextColor
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.usesAdaptiveColorMappingForDarkAppearance = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.typingAttributes = [
            .font: NSFont.preferredFont(forTextStyle: .body),
            .foregroundColor: NSColor.textColor
        ]
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor.selectedTextBackgroundColor,
            .foregroundColor: NSColor.selectedTextColor
        ]
        textView.onOptionEnter = { [weak coordinator = context.coordinator] in
            coordinator?.onOptionEnter?()
        }
        textView.delegate = context.coordinator
        textView.string = text

        scroll.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.didAutoFocus = false

        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }

        if textView.string != text {
            context.coordinator.isProgrammaticChange = true
            textView.string = text
            context.coordinator.isProgrammaticChange = false
        }

        let maxLength = (textView.string as NSString).length
        let location = min(max(0, selectedRange.location), maxLength)
        let length = min(max(0, selectedRange.length), maxLength - location)
        let clamped = NSRange(location: location, length: length)

        if !NSEqualRanges(textView.selectedRange(), clamped) {
            context.coordinator.isProgrammaticChange = true
            textView.setSelectedRange(clamped)
            context.coordinator.isProgrammaticChange = false
        }

        if autoFocus, context.coordinator.didAutoFocus == false {
            context.coordinator.didAutoFocus = true
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(textView)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        @Binding var selectedRange: NSRange
        var onOptionEnter: (() -> Void)?
        weak var textView: NSTextView?
        var isProgrammaticChange = false
        var didAutoFocus = false

        init(text: Binding<String>, selectedRange: Binding<NSRange>, onOptionEnter: (() -> Void)?) {
            _text = text
            _selectedRange = selectedRange
            self.onOptionEnter = onOptionEnter
        }

        func textDidChange(_ notification: Notification) {
            guard !isProgrammaticChange, let textView else { return }
            text = textView.string
            selectedRange = textView.selectedRange()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isProgrammaticChange, let textView else { return }
            selectedRange = textView.selectedRange()
        }
    }
}

private final class FocusTextView: NSTextView {
    var onOptionEnter: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isOptionEnter = flags == .option && (event.keyCode == 36 || event.keyCode == 76)
        if isOptionEnter {
            onOptionEnter?()
            return
        }

        super.keyDown(with: event)
    }
}

private struct SmartBoardEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let initialValue: SmartBoardDefinition?
    let discussionOptions: [String]
    let onSave: (SmartBoardDefinition) -> Void

    @State private var name: String
    @State private var discussionPath: String
    @State private var subjectContains: String
    @State private var replyContains: String
    @State private var nickContains: String
    @State private var unreadOnly: Bool

    init(
        initialValue: SmartBoardDefinition?,
        discussionOptions: [String],
        onSave: @escaping (SmartBoardDefinition) -> Void
    ) {
        self.initialValue = initialValue
        self.discussionOptions = discussionOptions.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        self.onSave = onSave

        _name = State(initialValue: initialValue?.name ?? "")
        _discussionPath = State(initialValue: initialValue?.discussionPath ?? "")
        _subjectContains = State(initialValue: initialValue?.subjectContains ?? "")
        _replyContains = State(initialValue: initialValue?.replyContains ?? "")
        _nickContains = State(initialValue: initialValue?.nickContains ?? "")
        _unreadOnly = State(initialValue: initialValue?.unreadOnly ?? false)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var title: String {
        initialValue == nil ? "Nouvelle discussion intelligente" : "Modifier la discussion intelligente"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)

            HStack {
                Text("Nom :")
                    .frame(width: 90, alignment: .trailing)
                TextField("Unread", text: $name)
            }

            GroupBox("Filtres de sujets") {
                VStack(spacing: 10) {
                    HStack {
                        Text("Discussion :")
                            .frame(width: 90, alignment: .trailing)
                        Picker("", selection: $discussionPath) {
                            Text("Toutes").tag("")
                            ForEach(discussionOptions, id: \.self) { option in
                                Text(option).tag(option)
                            }
                        }
                        .labelsHidden()
                    }

                    HStack {
                        Text("Sujet :")
                            .frame(width: 90, alignment: .trailing)
                        TextField("", text: $subjectContains)
                    }

                    HStack {
                        Text("Réponse :")
                            .frame(width: 90, alignment: .trailing)
                        TextField("", text: $replyContains)
                    }

                    HStack {
                        Text("Pseudo :")
                            .frame(width: 90, alignment: .trailing)
                        TextField("", text: $nickContains)
                    }

                    HStack(spacing: 8) {
                        Text("Non-lu :")
                            .frame(width: 90, alignment: .trailing)
                        Toggle("Oui", isOn: $unreadOnly)
                            .toggleStyle(.checkbox)
                        Spacer()
                    }
                }
                .padding(.vertical, 4)
            }

            HStack {
                Spacer()
                Button("Annuler") {
                    dismiss()
                }
                Button("Sauvegarder") {
                    let value = SmartBoardDefinition(
                        id: initialValue?.id ?? UUID().uuidString,
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                        discussionPath: discussionPath,
                        subjectContains: subjectContains,
                        replyContains: replyContains,
                        nickContains: nickContains,
                        unreadOnly: unreadOnly
                    )
                    onSave(value)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}

// MARK: - NewBoardView

private enum PermissionLevel: String, CaseIterable, Identifiable {
    case none
    case readWrite
    case readOnly
    case writeOnly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "Aucun acces"
        case .readWrite: return "Lecture et ecriture"
        case .readOnly: return "Lecture seulement"
        case .writeOnly: return "Ecriture seulement"
        }
    }

    var read: Bool {
        switch self {
        case .none: return false
        case .readWrite, .readOnly: return true
        case .writeOnly: return false
        }
    }

    var write: Bool {
        switch self {
        case .readWrite, .writeOnly: return true
        case .none, .readOnly: return false
        }
    }

    static func from(read: Bool, write: Bool) -> PermissionLevel {
        switch (read, write) {
        case (false, false): return .none
        case (true, true): return .readWrite
        case (true, false): return .readOnly
        case (false, true): return .writeOnly
        }
    }
}

private struct NewBoardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ConnectionRuntime.self) private var runtime

    let parentBoard: Board?

    @State private var boardName: String = ""
    @State private var ownerSelection: String = ""
    @State private var groupSelection: String = ""
    @State private var ownerLevel: PermissionLevel = .readWrite
    @State private var groupLevel: PermissionLevel = .none
    @State private var everyoneLevel: PermissionLevel = .readWrite
    @State private var ownerNames: [String] = []
    @State private var groupNames: [String] = []
    @State private var isLoadingAccounts = false
    @State private var isCreating: Bool = false

    private var parentPathLabel: String {
        parentBoard?.path ?? "/"
    }

    private var resolvedPath: String {
        let trimmedName = boardName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        let parentPath = (parentBoard?.path ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard !trimmedName.isEmpty else { return "" }
        guard !parentPath.isEmpty else { return trimmedName }
        return "\(parentPath)/\(trimmedName)"
    }

    private var canCreate: Bool {
        !resolvedPath.isEmpty &&
        runtime.hasPrivilege("wired.account.board.add_boards") &&
        !isCreating
    }

    private var ownerOptions: [String] {
        var values = ownerNames
        if !ownerSelection.isEmpty && !values.contains(ownerSelection) {
            values.append(ownerSelection)
        }
        return values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var groupOptions: [String] {
        var values = groupNames
        if !groupSelection.isEmpty && !values.contains(groupSelection) {
            values.append(groupSelection)
        }
        return values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("New Board")
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            Form {
                Section("Location") {
                    LabeledContent("Parent", value: parentPathLabel)
                    TextField("Board Name", text: $boardName)
                    if !resolvedPath.isEmpty {
                        LabeledContent("Path", value: resolvedPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Permissions") {
                    Picker("Proprietaire", selection: $ownerSelection) {
                        Text("Aucun").tag("")
                        ForEach(ownerOptions, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .disabled(isLoadingAccounts)

                    Picker("Acces proprietaire", selection: $ownerLevel) {
                        ForEach(PermissionLevel.allCases) { level in
                            Text(level.label).tag(level)
                        }
                    }

                    Picker("Groupe", selection: $groupSelection) {
                        Text("Aucun").tag("")
                        ForEach(groupOptions, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .disabled(isLoadingAccounts)

                    Picker("Acces groupe", selection: $groupLevel) {
                        ForEach(PermissionLevel.allCases) { level in
                            Text(level.label).tag(level)
                        }
                    }

                    Picker("Tout le monde", selection: $everyoneLevel) {
                        ForEach(PermissionLevel.allCases) { level in
                            Text(level.label).tag(level)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .overlay {
                if isLoadingAccounts {
                    ProgressView("Chargement des comptes…")
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Create") { createBoard() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate)
            }
            .padding()
        }
        .frame(width: 520, height: 460)
        .task {
            await loadAccounts()
        }
    }

    private func createBoard() {
        isCreating = true
        Task {
            do {
                try await runtime.addBoard(
                    path: resolvedPath,
                    owner: ownerSelection.trimmingCharacters(in: .whitespacesAndNewlines),
                    ownerRead: ownerLevel.read,
                    ownerWrite: ownerLevel.write,
                    group: groupSelection.trimmingCharacters(in: .whitespacesAndNewlines),
                    groupRead: groupLevel.read,
                    groupWrite: groupLevel.write,
                    everyoneRead: everyoneLevel.read,
                    everyoneWrite: everyoneLevel.write
                )
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    runtime.lastError = error
                    isCreating = false
                }
            }
        }
    }

    @MainActor
    private func loadAccounts() async {
        isLoadingAccounts = true
        defer { isLoadingAccounts = false }

        do {
            async let users = runtime.listAccountUserNames()
            async let groups = runtime.listAccountGroupNames()
            ownerNames = try await users
            groupNames = try await groups
        } catch {
            runtime.lastError = error
        }
    }
}

// MARK: - EditBoardPermissionsView

private struct EditBoardPermissionsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ConnectionRuntime.self) private var runtime

    let board: Board

    @State private var ownerSelection: String
    @State private var groupSelection: String
    @State private var ownerLevel: PermissionLevel
    @State private var groupLevel: PermissionLevel
    @State private var everyoneLevel: PermissionLevel
    @State private var ownerNames: [String] = []
    @State private var groupNames: [String] = []
    @State private var isLoading = true
    @State private var isSaving = false

    init(board: Board) {
        self.board = board
        self._ownerSelection = State(initialValue: board.owner)
        self._groupSelection = State(initialValue: board.group)
        self._ownerLevel = State(initialValue: .from(read: board.ownerRead, write: board.ownerWrite))
        self._groupLevel = State(initialValue: .from(read: board.groupRead, write: board.groupWrite))
        self._everyoneLevel = State(initialValue: .from(read: board.everyoneRead, write: board.everyoneWrite))
    }

    private var canSave: Bool {
        runtime.hasPrivilege("wired.account.board.set_board_info") && !isSaving && !isLoading
    }

    private var ownerOptions: [String] {
        var values = ownerNames
        if !ownerSelection.isEmpty && !values.contains(ownerSelection) {
            values.append(ownerSelection)
        }
        return values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var groupOptions: [String] {
        var values = groupNames
        if !groupSelection.isEmpty && !values.contains(groupSelection) {
            values.append(groupSelection)
        }
        return values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Board Permissions")
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            Form {
                Section("Board") {
                    LabeledContent("Path", value: board.path)
                }

                Section("Permissions") {
                    Picker("Proprietaire", selection: $ownerSelection) {
                        Text("Aucun").tag("")
                        ForEach(ownerOptions, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .disabled(isLoading || isSaving)

                    Picker("Acces proprietaire", selection: $ownerLevel) {
                        ForEach(PermissionLevel.allCases) { level in
                            Text(level.label).tag(level)
                        }
                    }
                    .disabled(isLoading || isSaving)

                    Picker("Groupe", selection: $groupSelection) {
                        Text("Aucun").tag("")
                        ForEach(groupOptions, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .disabled(isLoading || isSaving)

                    Picker("Acces groupe", selection: $groupLevel) {
                        ForEach(PermissionLevel.allCases) { level in
                            Text(level.label).tag(level)
                        }
                    }
                    .disabled(isLoading || isSaving)

                    Picker("Tout le monde", selection: $everyoneLevel) {
                        ForEach(PermissionLevel.allCases) { level in
                            Text(level.label).tag(level)
                        }
                    }
                    .disabled(isLoading || isSaving)
                }
            }
            .formStyle(.grouped)
            .overlay {
                if isLoading {
                    ProgressView("Loading permissions…")
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding()
        }
        .frame(width: 560, height: 360)
        .task {
            await load()
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        if runtime.hasPrivilege("wired.account.board.get_board_info") {
            do {
                try await runtime.getBoardInfo(path: board.path)
            } catch {
                runtime.lastError = error
            }
        }

        do {
            async let users = runtime.listAccountUserNames()
            async let groups = runtime.listAccountGroupNames()
            ownerNames = try await users
            groupNames = try await groups
        } catch {
            runtime.lastError = error
        }

        ownerSelection = board.owner
        groupSelection = board.group
        ownerLevel = .from(read: board.ownerRead, write: board.ownerWrite)
        groupLevel = .from(read: board.groupRead, write: board.groupWrite)
        everyoneLevel = .from(read: board.everyoneRead, write: board.everyoneWrite)
    }

    private func save() {
        isSaving = true
        Task {
            do {
                try await runtime.setBoardInfo(
                    path: board.path,
                    owner: ownerSelection.trimmingCharacters(in: .whitespacesAndNewlines),
                    ownerRead: ownerLevel.read,
                    ownerWrite: ownerLevel.write,
                    group: groupSelection.trimmingCharacters(in: .whitespacesAndNewlines),
                    groupRead: groupLevel.read,
                    groupWrite: groupLevel.write,
                    everyoneRead: everyoneLevel.read,
                    everyoneWrite: everyoneLevel.write
                )
                try await runtime.getBoardInfo(path: board.path)
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    runtime.lastError = error
                    isSaving = false
                }
            }
        }
    }
}

// MARK: - BoardRowView

private struct BoardRowView: View {
    let board: Board

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "newspaper")
                .foregroundStyle(board.writable ? .primary : .secondary)
            Text(board.name)
            Spacer(minLength: 8)
            if board.unreadPostsCount > 0 {
                Text(board.unreadPostsCount > 99 ? "99+" : "\(board.unreadPostsCount)")
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .frame(minWidth: 20, minHeight: 18)
                    .background(Capsule().fill(Color.accentColor))
            }
        }
    }
}

// MARK: - ThreadRowView

private struct ThreadRowView: View {
    let thread: BoardThread
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 5) {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 8, height: 8)
                .opacity(thread.unreadPostsCount > 0 ? 1 : 0)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(thread.subject)
                        .font(.headline)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                    Spacer(minLength: 6)
                if thread.unreadPostsCount > 0 {
                    Text(thread.unreadPostsCount > 99 ? "99+" : "\(thread.unreadPostsCount)")
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .frame(minWidth: 20, minHeight: 18)
                        .background(Capsule().fill(Color.accentColor))
                }
                }

                HStack(spacing: 6) {
                    Text(thread.nick)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if thread.replies > 0 {
                        Label("\(thread.replies)", systemImage: "bubble.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(Self.dateFormatter.string(from: thread.lastReplyDate ?? thread.postDate))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - PostsDetailView

private struct PostsDetailView: View {
    @Environment(ConnectionRuntime.self) private var runtime
    private let bottomAnchorID = "posts-bottom-anchor"

    let boardPath: String
    let threadUUID: String
    @State private var postToEdit: BoardPost?
    @State private var postToDelete: BoardPost?
    @State private var replyComposerContext: ReplyComposerContext?

    private struct ReplyComposerContext: Identifiable {
        let id = UUID()
        let initialText: String
    }
    
    private var thread: BoardThread? {
        runtime.thread(boardPath: boardPath, uuid: threadUUID)
    }

    private func canEditPost(_ post: BoardPost) -> Bool {
        guard !post.isThreadBody else { return false }
        return runtime.hasPrivilege("wired.account.board.edit_all_threads_and_posts")
        || (runtime.hasPrivilege("wired.account.board.edit_own_threads_and_posts") && post.isOwn)
    }

    private func canDeletePost(_ post: BoardPost) -> Bool {
        guard !post.isThreadBody else { return false }
        return runtime.hasPrivilege("wired.account.board.delete_all_threads_and_posts")
        || (runtime.hasPrivilege("wired.account.board.delete_own_threads_and_posts") && post.isOwn)
    }

    private var canReplyToThread: Bool {
        runtime.board(path: boardPath)?.writable ?? false
    }

    private func makeQuotedReplyText(from post: BoardPost, selectedText: String?) -> String {
        let chosen = (selectedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
        ? selectedText!.trimmingCharacters(in: .whitespacesAndNewlines)
        : post.text.trimmingCharacters(in: .whitespacesAndNewlines)

        let date = PostRowView.dateString(post.postDate)
        let lines = chosen.components(separatedBy: .newlines)
        let quotedBlock = ([ "\(post.nick) (\(date))" ] + lines).map { "> \($0)" }.joined(separator: "\n")
        return quotedBlock + "\n\n"
    }

    private func openReplyFromPost(_ post: BoardPost, selectedText: String?) {
        guard canReplyToThread else { return }
        let prefill = makeQuotedReplyText(from: post, selectedText: selectedText)
        replyComposerContext = ReplyComposerContext(initialText: prefill)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = false) {
        let action = {
            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
        }

        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.2), action)
            } else {
                action()
            }
        }
    }

    private func sortedPosts(_ posts: [BoardPost]) -> [BoardPost] {
        posts.sorted { lhs, rhs in
            if lhs.isThreadBody != rhs.isThreadBody {
                return lhs.isThreadBody && !rhs.isThreadBody
            }
            if lhs.postDate != rhs.postDate {
                return lhs.postDate < rhs.postDate
            }
            return lhs.uuid < rhs.uuid
        }
    }

    var body: some View {
        Group {
            if let thread {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            if !thread.postsLoaded {
                                ProgressView("Loading posts…")
                                    .padding(40)
                            } else if thread.posts.isEmpty {
                                ContentUnavailableView("No Posts", systemImage: "text.alignleft")
                                    .padding(40)
                            } else {
                                ForEach(sortedPosts(thread.posts)) { post in
                                    PostRowView(
                                        post: post,
                                        canReply: canReplyToThread,
                                        canEdit: canEditPost(post),
                                        canDelete: canDeletePost(post),
                                        onReply: { openReplyFromPost(post, selectedText: nil) },
                                        onQuote: { selectedText in openReplyFromPost(post, selectedText: selectedText) },
                                        onEdit: { postToEdit = post },
                                        onDelete: { postToDelete = post }
                                    )
                                        .padding(.horizontal)
                                    Divider()
                                        .padding(.horizontal)
                                }
                            }
                            Color.clear
                                .frame(height: 1)
                                .id(bottomAnchorID)
                        }
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                    .onAppear {
                        if thread.postsLoaded {
                            scrollToBottom(proxy)
                        }
                    }
                    .onChange(of: thread.postsLoaded) { _, loaded in
                        guard loaded else { return }
                        scrollToBottom(proxy)
                    }
                    .onChange(of: thread.posts.count) { _, _ in
                        guard thread.postsLoaded else { return }
                        scrollToBottom(proxy, animated: true)
                    }
                }
            } else {
                ContentUnavailableView("Thread unavailable", systemImage: "exclamationmark.triangle")
            }
        }
        .sheet(item: $postToEdit) { post in
            EditPostView(post: post, thread: thread)
                .environment(runtime)
        }
        .sheet(item: $replyComposerContext) { context in
            if let thread {
                ReplyView(thread: thread, initialText: context.initialText)
                    .environment(runtime)
            }
        }
        .confirmationDialog(
            "Delete post?",
            isPresented: Binding(
                get: { postToDelete != nil },
                set: { if !$0 { postToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let post = postToDelete, let thread else { return }
                Task {
                    do {
                        try await runtime.deletePost(uuid: post.uuid)
                        try await runtime.getPosts(forThread: thread)
                        await MainActor.run { postToDelete = nil }
                    } catch {
                        await MainActor.run {
                            runtime.lastError = error
                            postToDelete = nil
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                postToDelete = nil
            }
        } message: {
            Text(postToDelete?.text ?? "")
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

// MARK: - PostRowView

private struct PostRowView: View {
    let post: BoardPost
    let canReply: Bool
    let canEdit: Bool
    let canDelete: Bool
    let onReply: () -> Void
    let onQuote: (String?) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var isHoveringText = false

    private struct TextSegment: Identifiable {
        enum Kind {
            case body
            case quote
        }

        let id = UUID()
        let kind: Kind
        let text: String
    }

    private struct QuoteLine: Identifiable {
        let id = UUID()
        let level: Int
        let text: String
    }
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    static func dateString(_ value: Date) -> String {
        dateFormatter.string(from: value)
    }

    private var renderedText: AttributedString {
        post.text.attributedWithMarkdownAndDetectedLinks(linkColor: .blue)
    }

    private var segments: [TextSegment] {
        var result: [TextSegment] = []
        var currentBody: [String] = []
        var currentQuote: [String] = []

        func flushBody() {
            guard !currentBody.isEmpty else { return }
            result.append(TextSegment(kind: .body, text: currentBody.joined(separator: "\n")))
            currentBody.removeAll()
        }

        func flushQuote() {
            guard !currentQuote.isEmpty else { return }
            result.append(TextSegment(kind: .quote, text: currentQuote.joined(separator: "\n")))
            currentQuote.removeAll()
        }

        for rawLine in post.text.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(">") {
                flushBody()
                currentQuote.append(rawLine)
            } else {
                flushQuote()
                currentBody.append(rawLine)
            }
        }

        flushBody()
        flushQuote()
        return result
    }

    private var imageURLs: [URL] {
        post.text.detectedHTTPImageURLs()
    }

    private func quoteLines(from text: String) -> [QuoteLine] {
        text.components(separatedBy: .newlines).compactMap { rawLine in
            parseQuoteLine(rawLine)
        }
    }

    private func parseQuoteLine(_ rawLine: String) -> QuoteLine? {
        let chars = Array(rawLine)
        var i = 0
        while i < chars.count, chars[i].isWhitespace { i += 1 }

        var level = 0
        while i < chars.count {
            while i < chars.count, chars[i].isWhitespace { i += 1 }
            guard i < chars.count, chars[i] == ">" else { break }
            level += 1
            i += 1
        }

        guard level > 0 else { return nil }

        let content = i < chars.count ? String(chars[i...]).trimmingCharacters(in: .whitespaces) : ""
        return QuoteLine(level: level, text: content.isEmpty ? " " : content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Author header
            HStack(spacing: 8) {
                if let iconData = post.icon, let img = NSImage(data: iconData) {
                    Image(nsImage: img)
                        .resizable()
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(post.nick)
                            .font(.headline)
                        if post.isUnread {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 8, height: 8)
                        }
                    }
                    Text(Self.dateString(post.postDate))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let editDate = post.editDate {
                    Text("Edited \(Self.dateFormatter.string(from: editDate))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            // Post body
            VStack(alignment: .leading, spacing: 8) {
                ForEach(segments) { segment in
                    switch segment.kind {
                    case .body:
                        Text(segment.text.attributedWithMarkdownAndDetectedLinks(linkColor: .blue))
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    case .quote:
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(quoteLines(from: segment.text)) { line in
                                HStack(alignment: .firstTextBaseline, spacing: 7) {
                                    HStack(spacing: 4) {
                                        ForEach(0..<max(1, line.level), id: \.self) { _ in
                                            RoundedRectangle(cornerRadius: 1)
                                                .fill(Color.secondary.opacity(0.33))
                                                .frame(width: 2, height: 15)
                                        }
                                    }
                                    Text(line.text.attributedWithMarkdownAndDetectedLinks(linkColor: .blue))
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.secondary.opacity(0.08))
                        )
                    }
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .pointerOnHover(isHovering: $isHoveringText)

            if !imageURLs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(imageURLs.prefix(3)), id: \.absoluteString) { url in
                        Link(destination: url) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .empty:
                                    ProgressView()
                                        .frame(maxWidth: .infinity, minHeight: 120)
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxWidth: 420)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                case .failure:
                                    Label(url.lastPathComponent, systemImage: "exclamationmark.triangle")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                @unknown default:
                                    EmptyView()
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .pointerOnHover()
                    }
                }
                .padding(.top, 4)
            }

            HStack(spacing: 10) {
                Spacer()
                if canReply {
                    Button("Reply") { onReply() }
                        .buttonStyle(.borderless)
                    Button("Quote") { onQuote(currentSelectedText()) }
                        .buttonStyle(.borderless)
                }
                if canEdit {
                    Button("Edit") { onEdit() }
                        .buttonStyle(.borderless)
                }
                if canDelete {
                    Button("Delete", role: .destructive) { onDelete() }
                        .buttonStyle(.borderless)
                }
            }
            .font(.caption)
        }
        .padding(.vertical, 12)
        .contextMenu {
            if canReply {
                Button("Reply") { onReply() }
                Button("Quote") { onQuote(currentSelectedText()) }
                Divider()
            }
            if canEdit {
                Button("Edit Post") { onEdit() }
            }
            if canDelete {
                Button("Delete Post", role: .destructive) { onDelete() }
            }
        }
    }

    private func currentSelectedText() -> String? {
        #if os(macOS)
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else { return nil }
        let range = textView.selectedRange()
        guard range.location != NSNotFound, range.length > 0 else { return nil }
        let ns = textView.string as NSString
        guard NSMaxRange(range) <= ns.length else { return nil }
        return ns.substring(with: range)
        #else
        return nil
        #endif
    }
}

// MARK: - Pointer Cursor

private struct PointerOnHoverModifier: ViewModifier {
    @State private var isHovering = false
    var externalIsHovering: Binding<Bool>?

    func body(content: Content) -> some View {
        #if os(macOS)
        content.onHover { hovering in
            if hovering {
                if !(externalIsHovering?.wrappedValue ?? isHovering) {
                    externalIsHovering?.wrappedValue = true
                    isHovering = true
                    NSCursor.pointingHand.push()
                }
            } else {
                if externalIsHovering?.wrappedValue ?? isHovering {
                    externalIsHovering?.wrappedValue = false
                    isHovering = false
                    NSCursor.pop()
                }
            }
        }
        #else
        content
        #endif
    }
}

private extension View {
    func pointerOnHover(isHovering: Binding<Bool>? = nil) -> some View {
        modifier(PointerOnHoverModifier(externalIsHovering: isHovering))
    }
}

// MARK: - BoardPathActionView

private struct BoardPathActionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ConnectionRuntime.self) private var runtime

    let title: String
    let actionLabel: String
    let initialPath: String
    let submit: (String) async throws -> Void

    @State private var path: String
    @State private var isSubmitting = false

    init(
        title: String,
        actionLabel: String,
        initialPath: String,
        submit: @escaping (String) async throws -> Void
    ) {
        self.title = title
        self.actionLabel = actionLabel
        self.initialPath = initialPath
        self.submit = submit
        self._path = State(initialValue: initialPath)
    }

    private var canSubmit: Bool {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != initialPath && !isSubmitting
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            Form {
                TextField("Path", text: $path)
                LabeledContent("Current", value: initialPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(actionLabel) { apply() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit)
            }
            .padding()
        }
        .frame(width: 520, height: 220)
    }

    private func apply() {
        isSubmitting = true
        Task {
            do {
                try await submit(path.trimmingCharacters(in: .whitespacesAndNewlines))
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    runtime.lastError = error
                    isSubmitting = false
                }
            }
        }
    }
}

// MARK: - EditThreadView

private struct EditThreadView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ConnectionRuntime.self) private var runtime

    let thread: BoardThread

    @State private var subject: String
    @State private var text: String = ""
    @State private var isSubmitting = false

    init(thread: BoardThread) {
        self.thread = thread
        self._subject = State(initialValue: thread.subject)
    }

    private var canSubmit: Bool {
        !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isSubmitting
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit Thread")
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                TextField("Subject", text: $subject)
                Text("Message")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                MarkdownComposer(text: $text, minHeight: 220, onOptionEnter: save)
            }
            .padding()

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit)
            }
            .padding()
        }
        .frame(width: 600, height: 430)
        .task {
            // Prefill body with currently loaded first post when available.
            if let firstPost = thread.posts.first {
                text = firstPost.text
            } else {
                try? await runtime.getPosts(forThread: thread)
                text = thread.posts.first?.text ?? ""
            }
        }
    }

    private func save() {
        guard canSubmit else { return }
        isSubmitting = true
        Task {
            do {
                try await runtime.editThread(
                    uuid: thread.uuid,
                    subject: subject.trimmingCharacters(in: .whitespacesAndNewlines),
                    text: text.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                try await runtime.getPosts(forThread: thread)
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    runtime.lastError = error
                    isSubmitting = false
                }
            }
        }
    }
}

// MARK: - MoveThreadView

private struct MoveThreadView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ConnectionRuntime.self) private var runtime

    let thread: BoardThread

    @State private var destinationPath: String
    @State private var isSubmitting = false

    init(thread: BoardThread) {
        self.thread = thread
        self._destinationPath = State(initialValue: thread.boardPath)
    }

    private var availableBoards: [Board] {
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

    private var canSubmit: Bool {
        !destinationPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && destinationPath != thread.boardPath
            && !isSubmitting
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Move Thread")
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            Form {
                TextField("Destination Path", text: $destinationPath)
                Picker("Destination", selection: $destinationPath) {
                    ForEach(availableBoards) { board in
                        Text(board.path).tag(board.path)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Move") { move() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit)
            }
            .padding()
        }
        .frame(width: 560, height: 280)
    }

    private func move() {
        isSubmitting = true
        Task {
            do {
                try await runtime.moveThread(
                    uuid: thread.uuid,
                    newBoardPath: destinationPath.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    runtime.lastError = error
                    isSubmitting = false
                }
            }
        }
    }
}

// MARK: - EditPostView

private struct EditPostView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ConnectionRuntime.self) private var runtime

    let post: BoardPost
    let thread: BoardThread?

    @State private var text: String
    @State private var isSubmitting = false

    init(post: BoardPost, thread: BoardThread?) {
        self.post = post
        self.thread = thread
        self._text = State(initialValue: post.text)
    }

    private var canSubmit: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSubmitting
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit Post")
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            MarkdownComposer(text: $text, minHeight: 200, onOptionEnter: save)
                .padding(8)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit)
            }
            .padding()
        }
        .frame(width: 560, height: 390)
    }

    private func save() {
        guard canSubmit else { return }
        isSubmitting = true
        Task {
            do {
                try await runtime.editPost(
                    uuid: post.uuid,
                    subject: thread?.subject ?? "",
                    text: text.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                if let thread {
                    try await runtime.getPosts(forThread: thread)
                }
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    runtime.lastError = error
                    isSubmitting = false
                }
            }
        }
    }
}
