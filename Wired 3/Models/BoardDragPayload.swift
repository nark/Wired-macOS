//
//  BoardDragPayload.swift
//  Wired-macOS
//

import Foundation
import CoreTransferable
import UniformTypeIdentifiers

extension UTType {
    static let wiredBoardItem = UTType(exportedAs: "com.read-write.wired.board-item-v2", conformingTo: .json)
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
        FileRepresentation(exportedContentType: .wiredBoardItem) { item in
            let url = try makeTemporaryFile(for: item)
            return SentTransferredFile(url, allowAccessingOriginalFile: true)
        }

        CodableRepresentation(contentType: .wiredBoardItem)
    }

    private static func makeTemporaryFile(for item: BoardDropItem) throws -> URL {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("wired-board-item-\(UUID().uuidString)")
            .appendingPathExtension("wboarditem")
        let data = try JSONEncoder().encode(item)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }
}
