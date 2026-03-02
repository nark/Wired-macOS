//
//  Board.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 01/03/2026.
//  Copyright © 2026 Read-Write. All rights reserved.
//

import SwiftUI
import WiredSwift

@Observable
@MainActor
final class Board: Identifiable {
    let id: UUID = UUID()

    var path: String
    var readable: Bool
    var writable: Bool

    // Permissions (from board_info)
    var owner: String = ""
    var group: String = ""
    var ownerRead: Bool = false
    var ownerWrite: Bool = false
    var groupRead: Bool = false
    var groupWrite: Bool = false
    var everyoneRead: Bool = false
    var everyoneWrite: Bool = false

    var threads: [BoardThread] = []
    var children: [Board]? = nil  // nil = leaf, [] = loaded empty, [...] = sub-boards

    var name: String { (path as NSString).lastPathComponent }
    var parentPath: String { (path as NSString).deletingLastPathComponent }

    init(path: String, readable: Bool = true, writable: Bool = false) {
        self.path     = path
        self.readable = readable
        self.writable = writable
    }

    func apply(_ message: P7Message) {
        if let v = message.string(forField: "wired.board.owner")         { owner       = v }
        if let v = message.string(forField: "wired.board.group")         { group       = v }
        if let v = message.bool(forField: "wired.board.owner.read")      { ownerRead   = v }
        if let v = message.bool(forField: "wired.board.owner.write")     { ownerWrite  = v }
        if let v = message.bool(forField: "wired.board.group.read")      { groupRead   = v }
        if let v = message.bool(forField: "wired.board.group.write")     { groupWrite  = v }
        if let v = message.bool(forField: "wired.board.everyone.read")   { everyoneRead  = v; readable = v }
        if let v = message.bool(forField: "wired.board.everyone.write")  { everyoneWrite = v; writable = v }
    }
}
