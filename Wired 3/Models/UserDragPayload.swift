//
//  UserDragPayload.swift
//  Wired-macOS
//

import Foundation
import CoreTransferable
import UniformTypeIdentifiers

extension UTType {
    static let wiredUser = UTType(exportedAs: "com.read-write.wired.user")
}

struct UserDragPayload: Codable, Transferable {
    let userID: UInt32
    let nick: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .wiredUser)
    }
}
