//
//  FileServiceProtocol.swift
//  Wired-macOS
//
//  Created by Rafaël Warnault on 11/01/2026.
//  Copyright © 2026 Read-Write. All rights reserved.
//

import WiredSwift
import Foundation

struct DropboxPermissions {
    let owner: String
    let group: String
    let ownerRead: Bool
    let ownerWrite: Bool
    let groupRead: Bool
    let groupWrite: Bool
    let everyoneRead: Bool
    let everyoneWrite: Bool
}

protocol FileServiceProtocol {
    func listDirectory(
        path: String,
        recursive: Bool,
        connection: AsyncConnection
    ) -> AsyncThrowingStream<FileItem, Error>
    
    func deleteFile(
        path: String,
        connection: AsyncConnection
    ) async throws

    func moveFile(
        from sourcePath: String,
        to destinationPath: String,
        connection: AsyncConnection
    ) async throws

    func setFileType(
        path: String,
        type: FileType,
        connection: AsyncConnection
    ) async throws

    func setFilePermissions(
        path: String,
        permissions: DropboxPermissions,
        connection: AsyncConnection
    ) async throws

    func getFileInfo(
        path: String,
        connection: AsyncConnection
    ) async throws -> FileItem

    func listUserNames(connection: AsyncConnection) async throws -> [String]
    func listGroupNames(connection: AsyncConnection) async throws -> [String]

    func subscribeDirectory(
        path: String,
        connection: AsyncConnection
    ) async throws

    func unsubscribeDirectory(
        path: String,
        connection: AsyncConnection
    ) async throws
}

final class FileService: FileServiceProtocol {
    func listDirectory(
        path: String,
        recursive: Bool = false,
        connection: AsyncConnection
    ) -> AsyncThrowingStream<FileItem, Error> {

        let message = P7Message(
            withName: "wired.file.list_directory",
            spec: spec!
        )
        message.addParameter(field: "wired.file.path", value: path)
        message.addParameter(field: "wired.file.recursive", value: recursive)

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

    func moveFile(
        from sourcePath: String,
        to destinationPath: String,
        connection: AsyncConnection
    ) async throws {
        let message = P7Message(
            withName: "wired.file.move",
            spec: spec!
        )

        message.addParameter(field: "wired.file.path", value: sourcePath)
        message.addParameter(field: "wired.file.new_path", value: destinationPath)

        let response = try await connection.sendAsync(message)

        if response?.name == "wired.error" {
            throw WiredError(message: response!)
        }
    }

    func setFileType(
        path: String,
        type: FileType,
        connection: AsyncConnection
    ) async throws {
        guard type != .file else { return }

        let message = P7Message(
            withName: "wired.file.set_type",
            spec: spec!
        )

        message.addParameter(field: "wired.file.path", value: path)
        message.addParameter(field: "wired.file.type", value: type.rawValue)

        let response = try await connection.sendAsync(message)

        if response?.name == "wired.error" {
            throw WiredError(message: response!)
        }
    }

    func setFilePermissions(
        path: String,
        permissions: DropboxPermissions,
        connection: AsyncConnection
    ) async throws {
        let message = P7Message(
            withName: "wired.file.set_permissions",
            spec: spec!
        )

        message.addParameter(field: "wired.file.path", value: path)
        message.addParameter(field: "wired.file.owner", value: permissions.owner)
        message.addParameter(field: "wired.file.owner.read", value: permissions.ownerRead)
        message.addParameter(field: "wired.file.owner.write", value: permissions.ownerWrite)
        message.addParameter(field: "wired.file.group", value: permissions.group)
        message.addParameter(field: "wired.file.group.read", value: permissions.groupRead)
        message.addParameter(field: "wired.file.group.write", value: permissions.groupWrite)
        message.addParameter(field: "wired.file.everyone.read", value: permissions.everyoneRead)
        message.addParameter(field: "wired.file.everyone.write", value: permissions.everyoneWrite)

        let response = try await connection.sendAsync(message)

        if response?.name == "wired.error" {
            throw WiredError(message: response!)
        }
    }

    func getFileInfo(
        path: String,
        connection: AsyncConnection
    ) async throws -> FileItem {
        let message = P7Message(
            withName: "wired.file.get_info",
            spec: spec!
        )

        message.addParameter(field: "wired.file.path", value: path)

        let response = try await connection.sendAsync(message)

        guard let response else {
            throw WiredError(withTitle: "File Info Error", message: "No response from server")
        }

        if response.name == "wired.error" {
            throw WiredError(message: response)
        }

        guard response.name == "wired.file.info" else {
            throw WiredError(withTitle: "File Info Error", message: "Invalid response: \(response.name ?? "unknown")")
        }

        return FileItem(response, connection: connection)
    }

    func listUserNames(connection: AsyncConnection) async throws -> [String] {
        let message = P7Message(withName: "wired.account.list_users", spec: spec!)
        var values: [String] = []

        for try await response in try connection.sendAndWaitMany(message) {
            if response.name == "wired.error" {
                throw WiredError(message: response)
            }

            if response.name == "wired.account.user_list",
               let name = response.string(forField: "wired.account.name"),
               !name.isEmpty {
                values.append(name)
            }
        }

        return Array(Set(values)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func listGroupNames(connection: AsyncConnection) async throws -> [String] {
        let message = P7Message(withName: "wired.account.list_groups", spec: spec!)
        var values: [String] = []

        for try await response in try connection.sendAndWaitMany(message) {
            if response.name == "wired.error" {
                throw WiredError(message: response)
            }

            if response.name == "wired.account.group_list",
               let name = response.string(forField: "wired.account.name"),
               !name.isEmpty {
                values.append(name)
            }
        }

        return Array(Set(values)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func subscribeDirectory(
        path: String,
        connection: AsyncConnection
    ) async throws {
        let message = P7Message(
            withName: "wired.file.subscribe_directory",
            spec: spec!
        )

        message.addParameter(field: "wired.file.path", value: path)

        let response = try await connection.sendAsync(message)

        if response?.name == "wired.error" {
            throw WiredError(message: response!)
        }
    }

    func unsubscribeDirectory(
        path: String,
        connection: AsyncConnection
    ) async throws {
        let message = P7Message(
            withName: "wired.file.unsubscribe_directory",
            spec: spec!
        )

        message.addParameter(field: "wired.file.path", value: path)

        let response = try await connection.sendAsync(message)

        if response?.name == "wired.error" {
            throw WiredError(message: response!)
        }
    }

}
