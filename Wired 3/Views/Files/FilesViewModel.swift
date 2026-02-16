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

struct RemoteTreeNode: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let level: Int
    let item: FileItem
}

@MainActor
final class FilesViewModel: ObservableObject {

    @Published var columns: [FileColumn] = []
    @Published var treeChildrenByPath: [String: [FileItem]] = [:]
    @Published var expandedTreePaths: Set<String> = ["/"]
    @Published var treeSelectionPath: String? = nil
    @Published var treeViewRevision: Int = 0
    
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
                    self.handleSelection(
                        newID,
                        in: index,
                        onColumnAppended: onColumnAppended
                    )
                }
            )
        }
    
    // MARK: -

    func loadRoot() async {
        _ = await loadColumn(for: root)
        await loadTreeRoot()
    }

    func loadColumn(for item: FileItem) async -> FileColumn? {
        guard let connection = runtime?.connection as? AsyncConnection,
              let fileService else {
            return nil
        }

        var files: [FileItem] = []

        do {
            for try await file in fileService.listDirectory(
                path: item.path,
                recursive: false,
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
                recursive: false,
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
    func reloadAll() async {
        for idx in columns.indices {
            await reloadColumn(at: idx)
        }
        await loadTreeRoot()
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
    func loadTreeRoot() async {
        guard let connection = runtime?.connection as? AsyncConnection,
              let fileService else { return }

        do {
            var items: [FileItem] = []
            for try await file in fileService.listDirectory(path: "/", recursive: false, connection: connection) {
                items.append(file)
            }
            treeChildrenByPath["/"] = items
            treeViewRevision &+= 1
        } catch {
            self.error = error
        }
    }

    @MainActor
    func ensureTreeChildren(for directoryPath: String) async {
        if treeChildrenByPath[directoryPath] != nil { return }
        guard let connection = runtime?.connection as? AsyncConnection,
              let fileService else { return }

        do {
            var items: [FileItem] = []
            for try await file in fileService.listDirectory(path: directoryPath, recursive: false, connection: connection) {
                items.append(file)
            }
            treeChildrenByPath[directoryPath] = items
            treeViewRevision &+= 1
        } catch {
            self.error = error
        }
    }

    @MainActor
    func toggleTreeExpansion(for path: String) async {
        if expandedTreePaths.contains(path) {
            expandedTreePaths.remove(path)
        } else {
            expandedTreePaths.insert(path)
            await ensureTreeChildren(for: path)
        }
    }

    @MainActor
    func visibleTreeNodes() -> [RemoteTreeNode] {
        var nodes: [RemoteTreeNode] = []

        func appendChildren(for path: String, level: Int) {
            guard let children = treeChildrenByPath[path] else { return }

            let sortedChildren = children.sorted {
                if ($0.type == .directory || $0.type == .uploads || $0.type == .dropbox) != ($1.type == .directory || $1.type == .uploads || $1.type == .dropbox) {
                    return ($0.type == .directory || $0.type == .uploads || $0.type == .dropbox)
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }

            for child in sortedChildren {
                nodes.append(RemoteTreeNode(path: child.path, level: level, item: child))
                if expandedTreePaths.contains(child.path) {
                    appendChildren(for: child.path, level: level + 1)
                }
            }
        }

        appendChildren(for: "/", level: 0)
        return nodes
    }

    @MainActor
    func selectTreeItem(_ item: FileItem) async {
        treeSelectionPath = item.path
        if item.type == .directory || item.type == .uploads || item.type == .dropbox {
            await ensureTreeChildren(for: item.path)
        }
        let includeSelf = (item.type == .directory || item.type == .uploads || item.type == .dropbox)
        await expandTreeAncestors(for: item.path, includeSelf: includeSelf)
        _ = await revealRemotePath(item.path)
    }

    @MainActor
    func selectedTreeItem() -> FileItem? {
        guard let selection = treeSelectionPath else { return nil }
        for (_, items) in treeChildrenByPath {
            if let found = items.first(where: { $0.path == selection }) {
                return found
            }
        }
        if selection == "/" {
            return FileItem("/", path: "/", type: .directory)
        }
        return nil
    }

    @MainActor
    func preselectColumnItem(id: UUID, at index: Int) {
        guard columns.indices.contains(index) else { return }
        columns[index].selection = id
    }

    @MainActor
    func selectColumnItem(
        id: UUID,
        at index: Int,
        onColumnAppended: @escaping (FileColumn) -> Void
    ) {
        handleSelection(id, in: index, onColumnAppended: onColumnAppended)
    }

    @MainActor
    func moveRemoteItem(from sourcePath: String, to targetDirectoryPath: String) async throws {
        guard let connection = runtime?.connection as? AsyncConnection,
              let fileService else { return }
        let sourceName = (sourcePath as NSString).lastPathComponent
        let destinationPath = (targetDirectoryPath as NSString).appendingPathComponent(sourceName)

        if normalizedRemotePath(sourcePath) == normalizedRemotePath(destinationPath) {
            return
        }

        try await fileService.moveFile(from: sourcePath, to: destinationPath, connection: connection)
        await reloadAll()
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
            (item.type == .directory || item.type == .uploads || item.type == .dropbox)
        else {
            if let id = newID,
               let selected = columns[index].items.first(where: { $0.id == id }) {
                treeSelectionPath = selected.path
                Task { @MainActor in
                    await self.expandTreeAncestors(for: selected.path, includeSelf: false)
                }
            } else {
                treeSelectionPath = columns[index].path
                Task { @MainActor in
                    await self.expandTreeAncestors(for: columns[index].path, includeSelf: true)
                }
            }
            return
        }

        treeSelectionPath = item.path

        Task {
            let newColumn = await loadColumn(for: item)

            if let column = newColumn {
                onColumnAppended(column)
            }
            await self.expandTreeAncestors(for: item.path, includeSelf: true)
        }
    }

    @MainActor
    func expandTreeAncestors(for path: String, includeSelf: Bool) async {
        let normalized = normalizedRemotePath(path)
        expandedTreePaths.insert("/")
        guard normalized != "/" else { return }

        let components = normalized
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }

        var current = ""
        let maxIndex = includeSelf ? components.count - 1 : max(components.count - 2, -1)
        guard maxIndex >= 0 else { return }

        for (idx, component) in components.enumerated() where idx <= maxIndex {
            current += "/" + component
            expandedTreePaths.insert(current)
            await ensureTreeChildren(for: current)
        }
    }
}
