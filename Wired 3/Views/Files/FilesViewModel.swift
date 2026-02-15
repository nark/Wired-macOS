//
//  FilesViewModel.swift
//  Wired-macOS
//
//  Created by Rafaël Warnault on 11/01/2026.
//  Copyright © 2026 Read-Write. All rights reserved.
//

import SwiftUI
import WiredSwift

extension Notification.Name {
    static let revealRemoteTransferPath = Notification.Name("revealRemoteTransferPath")
}

struct RemoteTransferPathRequest {
    let connectionID: UUID
    let path: String
}

@MainActor
final class FilesViewModel: ObservableObject {

    @Published var columns: [FileColumn] = []
    
    @Published var showFilesBrowser: Bool = false
    @Published var showCreateFolderSheet: Bool = false
    @Published var showDeleteConfirmation: Bool = false
    
    @Published var error: Error? = nil
    
    var fileService: FileServiceProtocol?
    private var runtime: ConnectionRuntime?
    private var root = FileItem("/", path: "/")

    // MARK: -
    
    static func empty() -> FilesViewModel {
        FilesViewModel()
    }
    
    func configure(
        fileService: FileServiceProtocol,
        runtime: ConnectionRuntime
    ) {
        self.fileService = fileService
        self.runtime = runtime
    }
    
    
    // MARK: -
    
    var selectedItem: FileItem? {
        guard let lastColumn = columns.last else {
            return nil
        }
                
        guard let selectedID = lastColumn.selection else {
            return FileItem(lastColumn.path.lastPathComponent, path: lastColumn.path, type: .directory)
        }
                
        guard let item = lastColumn.items.first(where: { $0.id == selectedID }) else {
            return nil
        }
        
        return item
    }
    
    func selectionBinding(
            column index: Int,
            onColumnAppended: @escaping (FileColumn) -> Void
        ) -> Binding<UUID?> {

            Binding(
                get: {
                    self.columns[index].selection
                },
                set: { newID in
                    Task { @MainActor in
                        self.handleSelection(
                            newID,
                            in: index,
                            onColumnAppended: onColumnAppended
                        )
                    }
                }
            )
        }
    
    // MARK: -

    func loadRoot() async {
        await loadColumn(for: root)
    }

    func loadColumn(for item: FileItem) async -> FileColumn? {
        guard let connection = runtime?.connection as? AsyncConnection else {
            return nil
        }

        var files: [FileItem] = []

        do {
            for try await file in fileService!.listDirectory(
                path: item.path,
                connection: connection
            ) {
                files.append(file)
            }

            let column = FileColumn(
                path: item.path,
                items: files
            )

            columns.append(column)
            return column

        } catch {
            print("loadColumn error:", error)
            self.error = error
            return nil
        }
    }
    
    @MainActor
    func reloadColumn(at index: Int) async {
        guard
            columns.indices.contains(index),
            let connection = runtime?.connection as? AsyncConnection,
            let fileService = fileService
        else { return }

        let path = columns[index].path
        let previousSelection = columns[index].selection

        var files: [FileItem] = []

        do {
            for try await file in fileService.listDirectory(
                path: path,
                connection: connection
            ) {
                files.append(file)
            }

            columns[index].items = files

            // 🔁 restaurer la sélection si possible
            if
                let selectedID = previousSelection,
                files.contains(where: { $0.id == selectedID })
            {
                columns[index].selection = selectedID
            } else {
                columns[index].selection = nil
            }

        } catch {
            print("reloadColumn error:", error)
            self.error = error
        }
    }
    
    @MainActor
    func reloadSelectedColumn() async {
        guard let index = columns.indices.last else { return }
        await reloadColumn(at: index)
    }
    
    @MainActor
    func deleteFile(_ path: String) async {
        guard   let connection = runtime?.connection as? AsyncConnection,
                let fileService = fileService else {
            return
        }
        
        do {
            try await fileService.deleteFile(path: path, connection: connection)
        } catch {
            self.error = error
        }
    }

    @MainActor
    func revealRemotePath(_ path: String) async -> Bool {
        let normalizedPath = normalizedRemotePath(path)
        if normalizedPath.isEmpty { return false }

        if columns.isEmpty {
            await loadRoot()
        }
        guard !columns.isEmpty else { return false }

        if normalizedPath == "/" {
            columns = Array(columns.prefix(1))
            columns[0].selection = nil
            return true
        }

        let components = normalizedPath
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }

        guard !components.isEmpty else { return false }

        var currentPath = ""
        var columnIndex = 0

        for (idx, component) in components.enumerated() {
            if !columns.indices.contains(columnIndex) {
                return false
            }

            currentPath += "/" + component

            if columns[columnIndex].items.isEmpty {
                await reloadColumn(at: columnIndex)
            }

            var item = columns[columnIndex].items.first(where: { normalizedRemotePath($0.path) == currentPath })

            if item == nil {
                await reloadColumn(at: columnIndex)
                item = columns[columnIndex].items.first(where: { normalizedRemotePath($0.path) == currentPath })
            }

            guard let matched = item else {
                return false
            }

            columns[columnIndex].selection = matched.id
            columns = Array(columns.prefix(columnIndex + 1))

            let isLastComponent = idx == components.count - 1
            if !isLastComponent && (matched.type == .directory || matched.type == .uploads || matched.type == .dropbox) {
                _ = await loadColumn(for: matched)
                columnIndex += 1
            }
        }

        return true
    }
}


private extension FilesViewModel {
    func normalizedRemotePath(_ path: String) -> String {
        if path == "/" { return "/" }
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmed.isEmpty { return "/" }
        return "/" + trimmed
    }

    func handleSelection(
        _ newID: UUID?,
        in index: Int,
        onColumnAppended: @escaping (FileColumn) -> Void
    ) {
        // 1️⃣ mettre à jour la sélection
        columns[index].selection = newID

        // 2️⃣ supprimer les colonnes à droite
        columns = Array(columns.prefix(index + 1))

        guard
            let id = newID,
            let item = columns[index].items.first(where: { $0.id == id }),
            item.type == .directory
        else { return }

        Task {
            let newColumn = await loadColumn(for: item)

            if let column = newColumn {
                onColumnAppended(column)
            }
        }
    }
}
