//
//  BoardThread.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 01/03/2026.
//  Copyright © 2026 Read-Write. All rights reserved.
//

import SwiftUI
import WiredSwift

@Observable
@MainActor
final class BoardThread: Identifiable, Equatable, Hashable {
    let id: UUID = UUID()

    static func == (lhs: BoardThread, rhs: BoardThread) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

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
    var unreadPostsCount: Int = 0
    var lastReadAt: Date?

    var posts: [BoardPost] = []
    var postsLoaded: Bool = false

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
