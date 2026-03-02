//
//  BoardsView.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 01/03/2026.
//  Copyright © 2026 Read-Write. All rights reserved.
//

import SwiftUI

// MARK: - BoardsView

struct BoardsView: View {
    @Environment(ConnectionRuntime.self) private var runtime

    @State private var selectedBoard:  Board?       = nil
    @State private var selectedThread: BoardThread? = nil
    @State private var showNewThread   = false

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
            // Threads are lazy-loaded when a board is selected
        }
    }

    // MARK: - Boards list

    private var boardsList: some View {
        Group {
            if runtime.boards.isEmpty && !runtime.boardsLoaded {
                ProgressView("Loading boards…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if runtime.boards.isEmpty {
                ContentUnavailableView("No Boards", systemImage: "newspaper")
            } else {
                List(runtime.boards, children: \.children, selection: $selectedBoard) { board in
                    BoardRowView(board: board)
                }
            }
        }
        .navigationTitle("Boards")
        .onChange(of: selectedBoard) { _, newBoard in
            selectedThread = nil
            guard let board = newBoard else { return }
            if board.threads.isEmpty {
                Task { try? await runtime.getThreads(forBoard: board) }
            }
        }
    }

    // MARK: - Threads list

    private var threadsList: some View {
        Group {
            if let board = selectedBoard {
                if board.threads.isEmpty {
                    ProgressView("Loading threads…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(board.threads, selection: $selectedThread) { thread in
                        ThreadRowView(thread: thread)
                    }
                }
            } else {
                ContentUnavailableView("Select a Board", systemImage: "text.bubble")
            }
        }
        .navigationTitle(selectedBoard?.name ?? "Threads")
        .toolbar {
            if let board = selectedBoard, board.writable {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showNewThread = true
                    } label: {
                        Label("New Thread", systemImage: "square.and.pencil")
                    }
                }
            }
        }
        .sheet(isPresented: $showNewThread) {
            if let board = selectedBoard {
                NewThreadView(board: board)
                    .environment(runtime)
            }
        }
        .onChange(of: selectedThread) { _, thread in
            guard let thread, !thread.postsLoaded else { return }
            Task { try? await runtime.getPosts(forThread: thread) }
        }
    }

    // MARK: - Posts detail

    private var postsDetail: some View {
        Group {
            if let thread = selectedThread {
                PostsDetailView(thread: thread)
                    .environment(runtime)
            } else {
                ContentUnavailableView("Select a Thread", systemImage: "text.alignleft")
            }
        }
    }
}

// MARK: - BoardRowView

private struct BoardRowView: View {
    let board: Board

    var body: some View {
        Label {
            Text(board.name)
        } icon: {
            Image(systemName: "newspaper")
                .foregroundStyle(board.writable ? .primary : .secondary)
        }
    }
}

// MARK: - ThreadRowView

private struct ThreadRowView: View {
    let thread: BoardThread

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(thread.subject)
                .font(.headline)
                .lineLimit(1)

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

                Text(thread.lastReplyDate ?? thread.postDate, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - PostsDetailView

private struct PostsDetailView: View {
    @Environment(ConnectionRuntime.self) private var runtime

    let thread: BoardThread

    @State private var showReply = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if !thread.postsLoaded {
                    ProgressView("Loading posts…")
                        .padding(40)
                } else if thread.posts.isEmpty {
                    ContentUnavailableView("No Posts", systemImage: "text.alignleft")
                        .padding(40)
                } else {
                    ForEach(thread.posts) { post in
                        PostRowView(post: post)
                            .padding(.horizontal)
                        Divider()
                            .padding(.horizontal)
                    }
                }
            }
        }
        .navigationTitle(thread.subject)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showReply = true
                } label: {
                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                }
            }
        }
        .sheet(isPresented: $showReply) {
            ReplyView(thread: thread)
                .environment(runtime)
        }
    }
}

// MARK: - PostRowView

private struct PostRowView: View {
    let post: BoardPost

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
                    Text(post.nick)
                        .font(.headline)
                    Text(post.postDate, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let editDate = post.editDate {
                    Text("Edited \(editDate, style: .relative)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            // Post body
            Text(post.text)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
    }
}
