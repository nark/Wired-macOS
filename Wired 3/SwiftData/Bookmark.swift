//
//  Item.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 18/12/2025.
//  Copyright © 2025 Read-Write. All rights reserved.
//

import Foundation
import SwiftData
import WiredSwift

@Model
final class Bookmark {
    @Attribute(.unique) var id: UUID
    var name: String = ""
    var hostname: String
    var login: String
    var connectAtStartup: Bool = false
    var autoReconnect: Bool = false
    var useCustomIdentity: Bool = false
    var customNick: String = ""
    var customStatus: String = ""
    var status: Status
    var lastMessageAt: Date?
    
    var cipherRawValue: UInt32 = P7Socket.CipherType.ECDH_CHACHA20_POLY1305.rawValue
    var cipher: P7Socket.CipherType {
        get { P7Socket.CipherType(rawValue: cipherRawValue) }
        set { cipherRawValue = newValue.rawValue }
    }
    
    var compressionRawValue: UInt32 = P7Socket.Compression.LZ4.rawValue
    var compression: P7Socket.Compression {
        get { P7Socket.Compression(rawValue: compressionRawValue) }
        set { compressionRawValue = newValue.rawValue }
    }
    
    var checksumRawValue: UInt32 = P7Socket.Checksum.HMAC_256.rawValue
    var checksum: P7Socket.Checksum {
        get { P7Socket.Checksum(rawValue: checksumRawValue) }
        set { checksumRawValue = newValue.rawValue }
    }
    
    enum Status: String, Codable {
        case disconnected
        case connecting
        case connected
        case error
    }
    
    init(id: UUID = UUID(), name: String, hostname: String, login: String) {
        self.id         = id
        self.hostname   = hostname
        self.login      = login
        self.status     = .disconnected
        self.name       = name
    }
    
    init(url: Url) {
        self.id         = UUID()
        self.hostname   = url.hostname
        self.login      = url.login
        self.status     = .disconnected
        self.name       = hostname
    }
    
    var url: Url {
        Url(withString: "wired://\(login)@\(hostname)")
    }
}

@Model
final class ErrorLogEntry {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var source: String
    var serverName: String
    var connectionID: UUID?
    var title: String
    var message: String
    var details: String

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        source: String,
        serverName: String,
        connectionID: UUID? = nil,
        title: String,
        message: String,
        details: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.source = source
        self.serverName = serverName
        self.connectionID = connectionID
        self.title = title
        self.message = message
        self.details = details
    }
}
