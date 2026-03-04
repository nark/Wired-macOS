//
//  BoardDragPayload.swift
//  Wired-macOS
//

import Foundation
import CoreTransferable
import UniformTypeIdentifiers

extension UTType {
    static let wiredBoardItem = UTType(exportedAs: "com.read-write.wired.board-item-v2", conformingTo: .data)
}

struct BoardDropItem: Codable, Transferable {
    let kind: String
    let identifier: String

    static func board(path: String) -> BoardDropItem {
        BoardDropItem(kind: "board", identifier: path)
    }

    static func thread(uuid: String) -> BoardDropItem {
        BoardDropItem(kind: "thread", identifier: uuid)
    }

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation { item in
            String(data: try JSONEncoder().encode(item), encoding: .utf8)!
        } importing: { string in
            try JSONDecoder().decode(BoardDropItem.self, from: Data(string.utf8))
        }
    }
}
