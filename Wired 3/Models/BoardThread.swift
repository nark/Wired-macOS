//
//  BoardThread.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 01/03/2026.
//  Copyright © 2026 Read-Write. All rights reserved.
//

import SwiftUI
import WiredSwift

struct BoardSearchResult: Identifiable, Hashable {
    let boardPath: String
    let threadUUID: String
    let postUUID: String?
    let subject: String
    let nick: String
    let postDate: Date
    let editDate: Date?
    let snippet: String

    var id: String {
        threadUUID + "|" + (postUUID ?? "thread")
    }

    init?(_ message: P7Message) {
        guard
            let boardPath = message.string(forField: "wired.board.board"),
            let threadUUID = message.uuid(forField: "wired.board.thread"),
            let subject = message.string(forField: "wired.board.subject"),
            let nick = message.string(forField: "wired.user.nick"),
            let postDate = message.date(forField: "wired.board.post_date"),
            let snippet = message.string(forField: "wired.board.snippet")
        else {
            return nil
        }

        self.boardPath = boardPath
        self.threadUUID = threadUUID
        self.postUUID = message.uuid(forField: "wired.board.post")
        self.subject = subject
        self.nick = nick
        self.postDate = postDate
        self.editDate = message.date(forField: "wired.board.edit_date")
        self.snippet = snippet
    }
}

@Observable
@MainActor
final class BoardThread: Identifiable, Equatable, Hashable {
    let id: UUID = UUID()

    nonisolated static func == (lhs: BoardThread, rhs: BoardThread) -> Bool { lhs.id == rhs.id }
    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var uuid: String
    var boardPath: String
    var subject: String
    var nick: String
    var postDate: Date
    var editDate: Date?
    var lastReplyDate: Date?
    var lastReplyUUID: String?
    var replies: Int
    var isOwn: Bool
    var isUnreadThread: Bool = false
    var unreadPostsCount: Int = 0
    /// Number of new reactions received from other users since this thread was last marked read.
    var unreadReactionCount: Int = 0

    var posts: [BoardPost] = []
    var postsLoaded: Bool = false

    /// Emoji list of the thread-body's reactions — populated lazily after first open.
    var topReactionEmojis: [String] = []

    init(uuid: String,
         boardPath: String,
         subject: String,
         nick: String,
         postDate: Date,
         replies: Int = 0,
         isOwn: Bool = false) {
        self.uuid          = uuid
        self.boardPath     = boardPath
        self.subject       = subject
        self.nick          = nick
        self.postDate      = postDate
        self.replies       = replies
        self.isOwn         = isOwn
    }

    func apply(_ message: P7Message) {
        if let v = message.string(forField: "wired.board.subject")          { subject       = v }
        if let v = message.uint32(forField: "wired.board.replies")          { replies       = Int(v) }
        if let v = message.date(forField: "wired.board.edit_date")          { editDate      = v }
        if let v = message.date(forField: "wired.board.latest_reply_date")  { lastReplyDate = v }
        if let v = message.uuid(forField: "wired.board.latest_reply")       { lastReplyUUID = v }
    }
}
