//
//  Board.swift
//  Wired
//
//  Created by Rafael Warnault on 27/03/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa
import WiredSwift

public class Board: ConnectionObject {
    public var name: String!
    public var path: String!

    public var readable: Bool!
    public var writable: Bool!

    // Extended permissions (populated via board_info / set_board_info)
    public var owner: String = ""
    public var group: String = ""
    public var ownerRead: Bool = false
    public var ownerWrite: Bool = false
    public var groupRead: Bool = false
    public var groupWrite: Bool = false
    public var everyoneRead: Bool = false
    public var everyoneWrite: Bool = false

    public var boards: [Board] = []

    public var threads: [BoardThread] = []
    public var threadsByUUID: [String: BoardThread] = [:]

    init(_ message: P7Message, connection: ServerConnection) {
        super.init(connection)

        if let p = message.string(forField: "wired.board.board") {
            self.path = p
        }

        self.name = (self.path as NSString).lastPathComponent

        if let r = message.bool(forField: "wired.board.readable") { self.readable = r }
        if let w = message.bool(forField: "wired.board.writable") { self.writable = w }
    }

    public var hasParent: Bool {
        return self.path.split(separator: "/").count > 1
    }

    public func addThread(_ thread: BoardThread) {
        self.threads.append(thread)
        self.threadsByUUID[thread.uuid] = thread
    }

    /// Updates path and name (used when server sends board_renamed / board_moved).
    public func rename(to newPath: String) {
        self.path = newPath
        self.name = (newPath as NSString).lastPathComponent
    }

    /// Applies full permission info from a wired.board.board_info message.
    public func applyInfo(_ message: P7Message) {
        if let v = message.string(forField: "wired.board.owner")         { self.owner       = v }
        if let v = message.string(forField: "wired.board.group")         { self.group       = v }
        if let v = message.bool(forField: "wired.board.owner.read")      { self.ownerRead   = v }
        if let v = message.bool(forField: "wired.board.owner.write")     { self.ownerWrite  = v }
        if let v = message.bool(forField: "wired.board.group.read")      { self.groupRead   = v }
        if let v = message.bool(forField: "wired.board.group.write")     { self.groupWrite  = v }
        if let v = message.bool(forField: "wired.board.everyone.read")   { self.everyoneRead  = v; self.readable = v }
        if let v = message.bool(forField: "wired.board.everyone.write")  { self.everyoneWrite = v; self.writable = v }
    }
}
