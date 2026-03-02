//
//  Post.swift
//  Wired
//
//  Created by Rafael Warnault on 27/03/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa
import WiredSwift

public class Post: ConnectionObject {
    public var uuid: String!
    public var text: String!
    public var nick: String!
    public var postDate: Date!
    public var editDate: Date!
    public var icon: NSImage!

    public var board: Board!
    public var thread: BoardThread!

    init(_ message: P7Message, board: Board, thread: BoardThread, connection: ServerConnection) {
        super.init(connection)

        self.board  = board
        self.thread = thread

        // wired.board.post_list uses wired.board.post for the post UUID;
        // wired.board.thread uses wired.board.thread for the thread-body UUID.
        if let p = message.uuid(forField: "wired.board.post") {
            self.uuid = p
        } else if let p = message.uuid(forField: "wired.board.thread") {
            self.uuid = p
        }

        if let p = message.string(forField: "wired.board.text") {
            self.text = p
        }

        if let p = message.string(forField: "wired.user.nick") {
            self.nick = p
        }

        if let p = message.date(forField: "wired.board.post_date") {
            self.postDate = p
        }

        if let p = message.date(forField: "wired.board.edit_date") {
            self.editDate = p
        }

        if let data = message.data(forField: "wired.user.icon") {
            self.icon = NSImage(data: data)
        }
    }
}
