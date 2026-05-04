//
//  FilesView+Operations.swift
//  Wired 3
//
//  Created by Codex on 08/04/2026.
//

import SwiftUI
import WiredSwift
#if os(macOS)
import AppKit
#endif

extension FilesView {
    var toolbar: some View {
        HStack {
            Picker("", selection: $filesViewModel.selectedFileViewType) {
                Image(systemName: "rectangle.split.3x1").tag(FileViewType.columns)
                Image(systemName: "list.bullet.indent").tag(FileViewType.tree)
            }
            .help("Display Mode")
            .pickerStyle(.segmented)
            .frame(width: 80)

            Divider()
                .frame(height: 16)

            Button {
                Task { await navigateHistory(backward: true) }
            } label: {
                Image(systemName: "chevron.left")
            }
            .help("Navigate Backward")
            .disabled(!canGoBack)

            Button {
                Task { await navigateHistory(backward: false) }
            } label: {
                Image(systemName: "chevron.right")
            }
            .help("Navigate Forward")
            .disabled(!canGoForward)

            Divider()
                .frame(height: 16)

            Button {
                Task {
                    switch filesViewModel.selectedFileViewType {
                    case .tree:
                        await filesViewModel.loadTreeRoot()
                    case .columns:
                        if filesViewModel.columns.isEmpty {
                            await filesViewModel.loadRoot()
                        } else {
                            await filesViewModel.reloadSelectedColumn()
                        }
                    }
                }
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .help("Reload Files")

            Divider()
                .frame(height: 16)

            Button {
                if let selectedFile = selectedDownloadableItem {
                    download([selectedFile])
                }
            } label: {
                Image(systemName: "arrow.down")
            }
            .help("Download File(s)")
            .disabled(selectedDownloadableItem == nil)

            Button {
                filesViewModel.showFilesBrowser = true
            } label: {
                Image(systemName: "arrow.up")
            }
            .help("Upload File(s)")
            .disabled(selectedDirectoryForUpload == nil || !(selectedDirectoryForUpload.map(canUpload(to:)) ?? false))

            Divider()
                .frame(height: 16)

            Button {
                guard let target = selectedDirectoryForUpload, canCreateFolder(in: target) else { return }
                createFolderTargetOverride = selectedDirectoryForUpload
                filesViewModel.showCreateFolderSheet = true
            } label: {
                Image(systemName: "folder.badge.plus")
            }
            .help("Create Folder")
            .disabled(selectedDirectoryForUpload == nil || !(selectedDirectoryForUpload.map(canCreateFolder(in:)) ?? false))

            Button {
                requestDelete(selectedDeletableItems)
            } label: {
                Image(systemName: "trash")
            }
            .help("Delete File(s)")
            .disabled(selectedDeletableItems.isEmpty)

            Spacer()

            if filesViewModel.isPerformingFileNetworkActivity {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 16, height: 16)
            }
        }
        .padding()
    }

    func triggerSearch() {
        guard filesViewModel.searchText.count >= 3 else { return }
        currentSearchTask?.cancel()
        currentSearchTask = Task {
            await filesViewModel.search(query: filesViewModel.searchText)
        }
    }

    func upload(urls: [URL], to targetDirectory: FileItem) {
        guard canUpload(to: targetDirectory) else { return }
        for url in urls {
            let accessStarted = url.startAccessingSecurityScopedResource()
            let localPath = url.path
            if let transfer = transfers.uploadTransfer(localPath, toDirectory: targetDirectory, with: connectionID, filesViewModel: filesViewModel) {
                transfers.onTransferTerminal(id: transfer.id) { terminal in
                    guard terminal.type == .upload else { return }
                    guard terminal.state == .stopped || terminal.state == .disconnected else { return }
                    let lowered = terminal.error.lowercased()
                    guard lowered.contains("wired.error.file_exists") || lowered.contains("file_exists") || lowered.contains("already exists") else { return }
                    let conflict = UploadConflict(
                        localPath: terminal.localPath ?? localPath,
                        remotePath: terminal.remotePath ?? targetDirectory.path.stringByAppendingPathComponent(path: (localPath as NSString).lastPathComponent)
                    )
                    DispatchQueue.main.async {
                        enqueueUploadConflict(conflict)
                    }
                }
            }
            if accessStarted {
                url.stopAccessingSecurityScopedResource()
            }
        }
    }

    func moveRemoteItem(from sourcePath: String, to destinationDirectory: FileItem, link: Bool = false) async throws {
        try await filesViewModel.moveRemoteItem(from: sourcePath, to: destinationDirectory.path, link: link)
    }

    func requestDelete(_ items: [FileItem]) {
        let unique = sanitizedDeleteSelection(from: uniqueItems(items).filter { canDelete(item: $0) })
        guard !unique.isEmpty else { return }
        pendingDeleteItems = unique
        showDeleteSelectionConfirmation = true
    }

    func download(_ items: [FileItem]) {
        let unique = uniqueItems(items)
        pendingDownloadItems = unique.filter { canDownload(item: $0) }
        processPendingDownloads()
    }

    @MainActor
    func askOverwrite(path: String) -> Bool {
#if os(macOS)
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("File Already Exists", comment: "")
        alert.informativeText = String(format: NSLocalizedString("A file already exists at:\n%@\n\nOverwrite it?", comment: ""), path)
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("Overwrite", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Stop", comment: ""))
        return alert.runModal() == .alertFirstButtonReturn
#else
        return false
#endif
    }

    func processPendingDownloads() {
        while !pendingDownloadItems.isEmpty {
            let item = pendingDownloadItems.removeFirst()
            switch transfers.queueDownload(item, with: connectionID, overwriteExistingFile: false) {
            case let .started(transfer), let .resumed(transfer):
                registerDownloadTerminalErrorHook(for: transfer, item: item)
                continue
            case let .needsOverwrite(destination):
                if askOverwrite(path: destination) {
                    switch transfers.queueDownload(item, with: connectionID, overwriteExistingFile: true) {
                    case let .started(transfer), let .resumed(transfer):
                        registerDownloadTerminalErrorHook(for: transfer, item: item)
                    default:
                        break
                    }
                }
                continue
            case .failed:
                continue
            }
        }
    }

    func registerDownloadTerminalErrorHook(for transfer: Transfer, item: FileItem) {
        transfers.onTransferTerminal(id: transfer.id) { terminal in
            guard terminal.type == .download else { return }
            guard terminal.state == .stopped || terminal.state == .disconnected else { return }

            let message = terminal.error.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !message.isEmpty else { return }

            DispatchQueue.main.async {
                filesViewModel.error = WiredError(
                    withTitle: "Download Error",
                    message: "Unable to download \"\(item.name)\":\n\(message)"
                )
            }
        }
    }

    func enqueueUploadConflict(_ conflict: UploadConflict) {
        if activeUploadConflict?.remotePath == conflict.remotePath {
            return
        }
        if pendingUploadConflicts.contains(where: { $0.remotePath == conflict.remotePath }) {
            return
        }
        pendingUploadConflicts.append(conflict)
        processPendingUploadConflicts()
    }

    func processPendingUploadConflicts() {
        if activeUploadConflict != nil {
            activeUploadConflict = nil
        }
        guard !pendingUploadConflicts.isEmpty else { return }
        activeUploadConflict = pendingUploadConflicts.removeFirst()
    }

    func uniqueItems(_ items: [FileItem]) -> [FileItem] {
        var seen: Set<String> = []
        var unique: [FileItem] = []
        for item in items {
            guard !seen.contains(item.path) else { continue }
            seen.insert(item.path)
            unique.append(item)
        }
        return unique
    }

    func sanitizedDeleteSelection(from items: [FileItem]) -> [FileItem] {
        let normalizedByPath = Dictionary(uniqueKeysWithValues: items.map { (normalizedRemotePath($0.path), $0) })
        let allPaths = Set(normalizedByPath.keys)

        return items.filter { item in
            let candidate = normalizedRemotePath(item.path)
            return !allPaths.contains { other in
                guard other != candidate else { return false }
                return isAncestorPath(candidate, of: other)
            }
        }
    }

    func isAncestorPath(_ ancestor: String, of descendant: String) -> Bool {
        let normalizedAncestor = normalizedRemotePath(ancestor)
        let normalizedDescendant = normalizedRemotePath(descendant)

        guard normalizedAncestor != normalizedDescendant else { return false }
        if normalizedAncestor == "/" {
            return normalizedDescendant != "/"
        }
        return normalizedDescendant.hasPrefix(normalizedAncestor + "/")
    }

    func normalizedRemotePath(_ path: String) -> String {
        if path == "/" { return "/" }
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmed.isEmpty { return "/" }
        return "/" + trimmed
    }

    func directoryPath(from path: String?) -> String? {
        guard let path else { return nil }
        if let item = itemForPath(path) {
            if item.type.isDirectoryLike {
                return normalizedRemotePath(item.path)
            }
            return normalizedRemotePath(item.path.stringByDeletingLastPathComponent)
        }
        if path == "/" {
            return "/"
        }
        return normalizedRemotePath(path.stringByDeletingLastPathComponent)
    }

    func registerNavigation(fromPrimarySelectionPath path: String?) {
        guard let directory = directoryPath(from: path) else { return }
        registerNavigation(toDirectoryPath: directory)
    }

    func registerNavigation(toDirectoryPath path: String) {
        let normalized = normalizedRemotePath(path)
        if normalized == currentDirectoryPath { return }
        if !isApplyingHistoryNavigation {
            backDirectoryHistory.append(currentDirectoryPath)
            forwardDirectoryHistory.removeAll()
        }
        currentDirectoryPath = normalized
    }

    @MainActor
    func applyHistoryNavigation(to directoryPath: String) async {
        let normalized = normalizedRemotePath(directoryPath)
        switch filesViewModel.selectedFileViewType {
        case .columns:
            let didReveal = await filesViewModel.revealRemotePath(normalized)
            if didReveal, normalized != "/",
               let columnIndex = filesViewModel.columns.indices.last,
               let selectedID = filesViewModel.columns[columnIndex].selection {
                filesViewModel.selectColumnItem(
                    id: selectedID,
                    at: columnIndex,
                    onColumnAppended: { _ in }
                )
            }
            updatePrimarySelectionPath(normalized)
        case .tree:
            _ = await filesViewModel.setTreeRoot(normalized)
            updatePrimarySelectionPath(normalized)
        }
    }

    @MainActor
    func navigateHistory(backward: Bool) async {
        if filesViewModel.isSearchMode {
            currentSearchTask?.cancel()
            currentSearchTask = nil
            filesViewModel.searchText = ""
            await filesViewModel.clearSearch()
        }

        if backward {
            guard let previous = backDirectoryHistory.popLast() else { return }
            forwardDirectoryHistory.append(currentDirectoryPath)
            isApplyingHistoryNavigation = true
            defer { isApplyingHistoryNavigation = false }
            await applyHistoryNavigation(to: previous)
            currentDirectoryPath = normalizedRemotePath(previous)
            return
        }

        guard let next = forwardDirectoryHistory.popLast() else { return }
        backDirectoryHistory.append(currentDirectoryPath)
        isApplyingHistoryNavigation = true
        defer { isApplyingHistoryNavigation = false }
        await applyHistoryNavigation(to: next)
        currentDirectoryPath = normalizedRemotePath(next)
    }

    @MainActor
    func navigateToBreadcrumbPath(_ path: String) async {
        let normalized = normalizedRemotePath(path)

        switch filesViewModel.selectedFileViewType {
        case .columns:
            let didReveal = await filesViewModel.revealRemotePath(normalized)
            guard didReveal else { return }

            if normalized != "/",
               let item = itemForPath(normalized),
               item.type.isDirectoryLike,
               let columnIndex = filesViewModel.columns.indices.last,
               let selectedID = filesViewModel.columns[columnIndex].selection {
                filesViewModel.selectColumnItem(
                    id: selectedID,
                    at: columnIndex,
                    onColumnAppended: { _ in }
                )
            }

            updatePrimarySelectionPath(normalized)
            registerNavigation(fromPrimarySelectionPath: normalized)

        case .tree:
            if let item = itemForPath(normalized), item.type.isDirectoryLike {
                guard await filesViewModel.setTreeRoot(normalized) else { return }
                updatePrimarySelectionPath(normalized)
                registerNavigation(toDirectoryPath: normalized)
                return
            }

            let parentPath = directoryPath(from: normalized) ?? "/"
            guard await filesViewModel.setTreeRoot(parentPath) else { return }

            if let refreshedItem = itemForPath(normalized) ?? filesViewModel.currentItem(path: normalized) {
                await filesViewModel.selectTreeItem(refreshedItem)
            } else {
                filesViewModel.treeSelectionPath = normalized
            }

            updatePrimarySelectionPath(normalized)
            registerNavigation(toDirectoryPath: parentPath)
        }
    }

    func presentInfo(for item: FileItem) {
        guard canGetInfo(for: item) else { return }
        infoSheetItem = item
    }
}
