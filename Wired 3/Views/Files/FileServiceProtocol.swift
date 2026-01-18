//
//  FileServiceProtocol.swift
//  Wired-macOS
//
//  Created by Rafaël Warnault on 11/01/2026.
//  Copyright © 2026 Read-Write. All rights reserved.
//

import WiredSwift

protocol FileServiceProtocol {
    func listDirectory(
        path: String,
        connection: AsyncConnection
    ) -> AsyncThrowingStream<FileItem, Error>
    
    func deleteFile(
        path: String,
        connection: AsyncConnection
    ) async throws
}

final class FileService: FileServiceProtocol {
    func listDirectory(
        path: String,
        connection: AsyncConnection
    ) -> AsyncThrowingStream<FileItem, Error> {

        let message = P7Message(
            withName: "wired.file.list_directory",
            spec: spec!
        )
        message.addParameter(field: "wired.file.path", value: path)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await response in try connection.sendAndWaitMany(message) {
                        if response.name == "wired.file.file_list" {
                            continuation.yield(
                                FileItem(response, connection: connection)
                            )
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    func deleteFile(
        path: String,
        connection: AsyncConnection
    ) async throws {
        let message = P7Message(
            withName: "wired.file.delete",
            spec: spec!
        )
        
        message.addParameter(field: "wired.file.path", value: path)
        
        let response = try await connection.sendAsync(message)
           
        if response?.name == "wired.error" {
            throw WiredError(message: response!)
        }
    }
}
