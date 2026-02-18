//
//  FileItem.swift
//  Wired-macOS
//
//  Created by Rafaël Warnault on 12/01/2026.
//  Copyright © 2026 Read-Write. All rights reserved.
//

import Foundation
import WiredSwift

enum FileType: UInt32, CustomStringConvertible {
    case file       = 0
    case directory  = 1
    case uploads    = 2
    case dropbox    = 3
    
    var description: String {
        switch self {
        case .file:
            "File"
        case .directory:
            "Directory"
        case .uploads:
            "Uploads"
        case .dropbox:
            "Drop Box"
        }
    }
}

public struct FileItem: Identifiable, Hashable {
    public let id = UUID()
    var name: String = ""
    var path: String = ""
    
    var type: FileType = .file
    var children: [FileItem]? = nil
    var directoryCount:Int = 0
    
    var dataSize:UInt64 = 0
    var rsrcSize:UInt64 = 0
    var creationDate: Date? = nil
    var modificationDate: Date? = nil
    var uploadDataSize:UInt64 = 0
    var uploadRsrcSize:UInt64 = 0
    var dataTransferred:UInt64 = 0
    var rsrcTransferred:UInt64 = 0
    
    var connection: AsyncConnection? = nil
    
    init(_ name: String, path: String, type: FileType = .file) {
        self.name = name
        self.path = path
        self.type = type
    }
    
    init(_ message: P7Message, connection: AsyncConnection) {
        self.connection = connection
                
        if let p = message.string(forField: "wired.file.path") {
            self.path = p
            self.name = self.path.lastPathComponent
        }
        if let t = message.uint32(forField: "wired.file.type") {
            self.type = FileType(rawValue: t) ?? .file
        }
        if let s = message.uint64(forField: "wired.file.data_size") {
            self.dataSize = s
        }
        if let s = message.uint64(forField: "wired.file.rsrc_size") {
            self.rsrcSize = s
        }
        if let s = message.uint32(forField: "wired.file.directory_count") {
            self.directoryCount = Int(s)
        }
        if let date = message.date(forField: "wired.file.creation_time") {
            self.creationDate = date
        }
        if let date = message.date(forField: "wired.file.modification_time") {
            self.modificationDate = date
        }
    }
}

struct FileColumn: Identifiable {
    let id = UUID()
    let path: String
    var items: [FileItem]
    var selection: UUID? = nil
}

enum FileViewType: Int {
    case tree
    case columns
}
