//
//  FilesView.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 09/01/2026.
//  Copyright © 2026 Read-Write. All rights reserved.
//

import SwiftUI
import WiredSwift
import UniformTypeIdentifiers
import CoreTransferable
#if os(macOS)
import AppKit
#endif

extension UTType {
    static let wiredRemoteFile = UTType(exportedAs: "com.read-write.wired.remote-file")
}

struct RemoteFileDragPayload: Codable, Transferable {
    let path: String
    let name: String
    let isDirectory: Bool

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .wiredRemoteFile)
    }
}

private func dragExportTypeIdentifier(forFileName fileName: String) -> String {
    let ext = (fileName as NSString).pathExtension
    guard !ext.isEmpty else { return UTType.data.identifier }
    return UTType(filenameExtension: ext)?.identifier ?? UTType.data.identifier
}

private func dragExportFileName(for item: FileItem) -> String {
    let name = item.name.isEmpty ? (item.path as NSString).lastPathComponent : item.name
    return name.isEmpty ? "file" : name
}

private func dragExportSuggestedName(forFileName fileName: String) -> String {
    let baseName = (fileName as NSString).deletingPathExtension
    let ext = (fileName as NSString).pathExtension
    if ext.isEmpty || baseName.isEmpty {
        return fileName
    }
    return baseName
}

private func dragExportTemporaryFileName(forFileName fileName: String) -> String {
    let baseName = (fileName as NSString).deletingPathExtension
    let ext = (fileName as NSString).pathExtension
    if ext.isEmpty || baseName.isEmpty {
        return fileName
    }
    return baseName
}

private func dragExportTemporaryURL(for item: FileItem) -> URL {
    let fileName = dragExportFileName(for: item)
    let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("WiredDragExports", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    return base.appendingPathComponent(dragExportTemporaryFileName(forFileName: fileName), isDirectory: false)
}

struct FilesView: View {
    @Environment(ConnectionController.self) private var connectionController
    @Environment(ConnectionRuntime.self) private var runtime
    @EnvironmentObject private var transfers: TransferManager

    var bookmark: Bookmark

    @ObservedObject var filesViewModel: FilesViewModel

    @State private var selectedFileViewType: FileViewType = .columns

    private var selectedItem: FileItem? {
        switch selectedFileViewType {
        case .columns:
            return filesViewModel.selectedItem
        case .tree:
            return filesViewModel.selectedTreeItem()
        }
    }

    private var selectedDirectoryForUpload: FileItem? {
        guard var selected = selectedItem else { return nil }
        if selected.type == .directory || selected.type == .uploads || selected.type == .dropbox {
            return selected
        }

        let parentPath = selected.path.stringByDeletingLastPathComponent
        selected = FileItem(parentPath.lastPathComponent, path: parentPath, type: .directory)
        return selected
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            Divider()

            switch selectedFileViewType {
            case .tree:
                FilesTreeView(
                    bookmark: bookmark,
                    filesViewModel: filesViewModel,
                    onUploadURLs: { urls, target in
                        upload(urls: urls, to: target)
                    },
                    onMoveRemoteItem: { sourcePath, destinationDirectory in
                        try await moveRemoteItem(from: sourcePath, to: destinationDirectory)
                    }
                )
                .environment(connectionController)
                .environment(runtime)
                .environmentObject(transfers)

            case .columns:
                FilesColumnsView(
                    bookmark: bookmark,
                    filesViewModel: filesViewModel,
                    onUploadURLs: { urls, target in
                        upload(urls: urls, to: target)
                    },
                    onMoveRemoteItem: { sourcePath, destinationDirectory in
                        try await moveRemoteItem(from: sourcePath, to: destinationDirectory)
                    }
                )
                .environment(connectionController)
                .environment(runtime)
                .environmentObject(transfers)
            }
        }
        .fileImporter(
            isPresented: $filesViewModel.showFilesBrowser,
            allowedContentTypes: [.data, .directory],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                if let target = selectedDirectoryForUpload {
                    upload(urls: urls, to: target)
                }
            case .failure(let error):
                filesViewModel.error = error
            }
        }
        .sheet(isPresented: $filesViewModel.showCreateFolderSheet) {
            if let selectedFile = selectedDirectoryForUpload {
                FileFormView(filesViewModel: filesViewModel, parentDirectory: selectedFile)
                    .environment(connectionController)
                    .environment(runtime)
            }
        }
        .alert("Delete File", isPresented: $filesViewModel.showDeleteConfirmation, actions: {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let item = selectedItem {
                    Task {
                        await filesViewModel.deleteFile(item.path)
                        await filesViewModel.reloadAll()
                    }
                }
            }
        }, message: {
            Text("Are you sure you want to delete this file? This operation is not recoverable.")
        })
        .errorAlert(error: $filesViewModel.error)
        .onChange(of: selectedFileViewType) { _, newValue in
            Task {
                if newValue == .tree {
                    await filesViewModel.loadTreeRoot()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .revealRemoteTransferPath)) { notification in
            guard let request = notification.object as? RemoteTransferPathRequest else { return }
            guard request.connectionID == bookmark.id else { return }

            Task { @MainActor in
                _ = await filesViewModel.revealRemotePath(request.path)
            }
        }
    }

    private var toolbar: some View {
        HStack {
            Picker("", selection: $selectedFileViewType) {
                Image(systemName: "list.bullet.indent").tag(FileViewType.tree)
                Image(systemName: "rectangle.split.3x1").tag(FileViewType.columns)
            }
            .pickerStyle(.segmented)
            .frame(width: 80)

            Button {
                Task {
                    switch selectedFileViewType {
                    case .tree:
                        await filesViewModel.loadTreeRoot()
                    case .columns:
                        await filesViewModel.reloadSelectedColumn()
                    }
                }
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }

            Button {
                if let selectedFile = selectedItem, selectedFile.type == .file {
                    transfers.download(selectedFile, with: bookmark.id)
                }
            } label: {
                Image(systemName: "arrow.down")
            }
            .disabled(selectedItem?.type != .file)

            Button {
                filesViewModel.showFilesBrowser = true
            } label: {
                Image(systemName: "arrow.up")
            }
            .disabled(selectedDirectoryForUpload == nil)

            Button {
                filesViewModel.showCreateFolderSheet = true
            } label: {
                Image(systemName: "folder.badge.plus")
            }
            .disabled(selectedDirectoryForUpload == nil)

            Button {
                filesViewModel.showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
            }
            .disabled(selectedItem == nil || selectedItem?.path == "/")

            Spacer()
        }
        .padding()
    }

    private func upload(urls: [URL], to targetDirectory: FileItem) {
        for url in urls {
            let accessStarted = url.startAccessingSecurityScopedResource()
            _ = transfers.upload(url.path, toDirectory: targetDirectory, with: bookmark.id, filesViewModel: filesViewModel)
            if accessStarted {
                url.stopAccessingSecurityScopedResource()
            }
        }
    }

    private func moveRemoteItem(from sourcePath: String, to destinationDirectory: FileItem) async throws {
        try await filesViewModel.moveRemoteItem(from: sourcePath, to: destinationDirectory.path)
    }
}

struct FilesTreeView: View {
    @State var bookmark: Bookmark
    @ObservedObject var filesViewModel: FilesViewModel
    @EnvironmentObject private var transfers: TransferManager

    let onUploadURLs: ([URL], FileItem) -> Void
    let onMoveRemoteItem: (_ sourcePath: String, _ destinationDirectory: FileItem) async throws -> Void

    var body: some View {
        List(filesViewModel.visibleTreeNodes()) { node in
            treeRow(node)
        }
        .onAppear {
            Task { await filesViewModel.loadTreeRoot() }
        }
        .background(Color.white)
    }

    @ViewBuilder
    private func treeRow(_ node: RemoteTreeNode) -> some View {
        let item = node.item
        let isDirectory = (item.type == .directory || item.type == .uploads || item.type == .dropbox)
        let isExpanded = filesViewModel.expandedTreePaths.contains(item.path)
        let isSelected = filesViewModel.treeSelectionPath == item.path

        HStack(spacing: 6) {
            Color.clear
                .frame(width: CGFloat(node.level) * 14, height: 1)

            if isDirectory {
                Button {
                    Task { await filesViewModel.toggleTreeExpansion(for: item.path) }
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(isSelected ? Color.white : Color.secondary)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 12, height: 1)
            }

            FinderFileIconView(item: item, size: 16)

            Text(item.name)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .lineLimit(1)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.accentColor : Color.clear)
        }
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onTapGesture {
            Task {
                await filesViewModel.selectTreeItem(item)
            }
        }
        .onDrag {
            Task { await filesViewModel.selectTreeItem(item) }
            return dragProvider(for: item, isDirectory: isDirectory)
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard isDirectory else { return false }
            onUploadURLs(urls, item)
            return !urls.isEmpty
        }
        .dropDestination(for: RemoteFileDragPayload.self) { payloads, _ in
            guard isDirectory else { return false }
            guard let payload = payloads.first else { return false }
            if payload.path == item.path || item.path.hasPrefix(payload.path + "/") {
                return false
            }
            Task {
                do {
                    try await onMoveRemoteItem(payload.path, item)
                } catch {
                    await MainActor.run { filesViewModel.error = error }
                }
            }
            return true
        }
        .contextMenu {
            if item.type == .file {
                Button("Download") {
                    transfers.download(item, with: bookmark.id)
                }
            }
        }
    }

    private func dragProvider(for item: FileItem, isDirectory: Bool) -> NSItemProvider {
        let provider = NSItemProvider()

        if let payloadData = try? JSONEncoder().encode(
            RemoteFileDragPayload(path: item.path, name: item.name, isDirectory: isDirectory)
        ) {
            provider.registerDataRepresentation(
                forTypeIdentifier: UTType.wiredRemoteFile.identifier,
                visibility: .ownProcess
            ) { completion in
                completion(payloadData, nil)
                return nil
            }
        }

        guard item.type == .file else { return provider }

        let fileName = dragExportFileName(for: item)
        let fileType = dragExportTypeIdentifier(forFileName: fileName)
        provider.suggestedName = dragExportSuggestedName(forFileName: fileName)

        provider.registerFileRepresentation(
            forTypeIdentifier: fileType,
            fileOptions: [],
            visibility: .all
        ) { completion in
            let progress = Progress(totalUnitCount: 100)

            Task {
                let destinationURL = dragExportTemporaryURL(for: item)
                let destinationPath = destinationURL.path

                if !FileManager.default.fileExists(atPath: destinationPath) {
                    await MainActor.run {
                        _ = self.transfers.download(item, to: destinationPath, with: self.bookmark.id)
                    }

                    let timeout = Date().addingTimeInterval(120)
                    while !FileManager.default.fileExists(atPath: destinationPath) && Date() < timeout {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                    }
                }

                if FileManager.default.fileExists(atPath: destinationPath) {
                    progress.completedUnitCount = 100
                    completion(destinationURL, false, nil)
                } else {
                    let error = NSError(
                        domain: "Wired.DragAndDrop",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Unable to prepare file for Finder drop."]
                    )
                    completion(nil, false, error)
                }
            }

            return progress
        }

        return provider
    }
}

struct FilesColumnsView: View {
    @State var bookmark: Bookmark

    @ObservedObject var filesViewModel: FilesViewModel
    @EnvironmentObject private var transfers: TransferManager

    let onUploadURLs: ([URL], FileItem) -> Void
    let onMoveRemoteItem: (_ sourcePath: String, _ destinationDirectory: FileItem) async throws -> Void

    @State private var columnWidths: [UUID: CGFloat] = [:]
    @State private var previewWidth: CGFloat = 320

    var body: some View {
        ScrollView(.horizontal) {
            ScrollViewReader { proxy in
                HStack(spacing: 0) {
                    ForEach(Array(filesViewModel.columns.enumerated()), id: \.element.id) { index, column in
                        List(
                            column.items
                        ) { item in
                            row(
                                item,
                                in: column,
                                columnIndex: index,
                                onColumnAppended: { appended in
                                    proxy.scrollTo(appended.id, anchor: .trailing)
                                }
                            )
                        }
                        .frame(width: width(for: column))
                        .background(column.selection != nil ? Color.gray.opacity(0.12) : .clear)
                        .id(column.id)

                        ColumnResizeHandle(width: binding(for: column.id))
                    }

                    FilePreviewColumn(selectedItem: filesViewModel.selectedItem)
                        .frame(width: previewWidth)

                    ColumnResizeHandle(width: $previewWidth)
                }
                .onAppear {
                    previewWidth = min(max(previewWidth, 240), 620)
                }
                .onChange(of: filesViewModel.columns.count) { _, _ in
                    guard let last = filesViewModel.columns.last else { return }
                    Task { @MainActor in
                        await Task.yield()
                        withAnimation(.smooth) {
                            proxy.scrollTo(last.id, anchor: .trailing)
                        }
                    }
                }
            }
        }
        .background(Color.white)
    }

    @ViewBuilder
    private func row(
        _ item: FileItem,
        in column: FileColumn,
        columnIndex: Int,
        onColumnAppended: @escaping (FileColumn) -> Void
    ) -> some View {
        let isDirectory = (item.type == .directory || item.type == .uploads || item.type == .dropbox)
        let destination = isDirectory ? item : FileItem((column.path as NSString).lastPathComponent, path: column.path, type: .directory)

        HStack {
            FinderFileIconView(item: item, size: 16)
            Text(item.name)
                .foregroundStyle(column.selection == item.id ? Color.white : Color.primary)
                .lineLimit(1)
            Spacer(minLength: 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .tag(item.id)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(column.selection == item.id ? Color.accentColor : Color.clear)
        }
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
        .listRowBackground(Color.clear)
        .onTapGesture {
            filesViewModel.selectColumnItem(
                id: item.id,
                at: columnIndex,
                onColumnAppended: onColumnAppended
            )
        }
        .onDrag {
            return dragProvider(for: item, isDirectory: isDirectory)
        }
        .dropDestination(for: URL.self) { urls, _ in
            onUploadURLs(urls, destination)
            return !urls.isEmpty
        }
        .dropDestination(for: RemoteFileDragPayload.self) { payloads, _ in
            guard let payload = payloads.first else { return false }
            if payload.path == destination.path || destination.path.hasPrefix(payload.path + "/") {
                return false
            }

            Task {
                do {
                    try await onMoveRemoteItem(payload.path, destination)
                } catch {
                    await MainActor.run { filesViewModel.error = error }
                }
            }
            return true
        }
        .contextMenu {
            if item.type == .file {
                Button("Download") {
                    transfers.download(item, with: bookmark.id)
                }
            }
        }
    }

    private func dragProvider(for item: FileItem, isDirectory: Bool) -> NSItemProvider {
        let provider = NSItemProvider()

        if let payloadData = try? JSONEncoder().encode(
            RemoteFileDragPayload(path: item.path, name: item.name, isDirectory: isDirectory)
        ) {
            provider.registerDataRepresentation(
                forTypeIdentifier: UTType.wiredRemoteFile.identifier,
                visibility: .ownProcess
            ) { completion in
                completion(payloadData, nil)
                return nil
            }
        }

        guard item.type == .file else { return provider }

        let fileName = dragExportFileName(for: item)
        let fileType = dragExportTypeIdentifier(forFileName: fileName)
        provider.suggestedName = dragExportSuggestedName(forFileName: fileName)

        provider.registerFileRepresentation(
            forTypeIdentifier: fileType,
            fileOptions: [],
            visibility: .all
        ) { completion in
            let progress = Progress(totalUnitCount: 100)

            Task {
                let destinationURL = dragExportTemporaryURL(for: item)
                let destinationPath = destinationURL.path

                if !FileManager.default.fileExists(atPath: destinationPath) {
                    await MainActor.run {
                        _ = self.transfers.download(item, to: destinationPath, with: self.bookmark.id)
                    }

                    let timeout = Date().addingTimeInterval(120)
                    while !FileManager.default.fileExists(atPath: destinationPath) && Date() < timeout {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                    }
                }

                if FileManager.default.fileExists(atPath: destinationPath) {
                    progress.completedUnitCount = 100
                    completion(destinationURL, false, nil)
                } else {
                    let error = NSError(
                        domain: "Wired.DragAndDrop",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Unable to prepare file for Finder drop."]
                    )
                    completion(nil, false, error)
                }
            }

            return progress
        }

        return provider
    }

    private func width(for column: FileColumn) -> CGFloat {
        min(max(columnWidths[column.id] ?? 240, 180), 620)
    }

    private func binding(for id: UUID) -> Binding<CGFloat> {
        Binding(
            get: { min(max(columnWidths[id] ?? 240, 180), 620) },
            set: { columnWidths[id] = min(max($0, 180), 620) }
        )
    }
}

private struct ColumnResizeHandle: View {
    @Binding var width: CGFloat
    @State private var dragStartWidth: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.22))
            .frame(width: 4)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragStartWidth == 0 {
                            dragStartWidth = width
                        }
                        width = min(max(dragStartWidth + value.translation.width, 180), 620)
                    }
                    .onEnded { _ in
                        dragStartWidth = 0
                    }
            )
    }
}

private struct FilePreviewColumn: View {
    let selectedItem: FileItem?

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Preview")
                .font(.headline)

            Divider()

            if let item = selectedItem {
                HStack(spacing: 10) {
                    FinderFileIconView(item: item, size: 48)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name.isEmpty ? item.path : item.name)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        Text(item.path)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                }

                Divider()

                Group {
                    infoRow("Type", item.type.description)
                    infoRow("Size", sizeString(for: item))
                    infoRow("Created", dateString(item.creationDate))
                    infoRow("Modified", dateString(item.modificationDate))
                    infoRow("Contains", containsString(for: item))
                }
            } else {
                Text("Select a file or folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(10)
        .background(Color.white)
    }

    @ViewBuilder
    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.caption)
                .lineLimit(1)
            Spacer()
        }
    }

    private func sizeString(for item: FileItem) -> String {
        if item.type == .directory || item.type == .uploads || item.type == .dropbox {
            return "-"
        }
        let total = Int64(item.dataSize + item.rsrcSize)
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }

    private func containsString(for item: FileItem) -> String {
        if item.type == .directory || item.type == .uploads || item.type == .dropbox {
            return "\(item.directoryCount)"
        }
        return "-"
    }

    private func dateString(_ date: Date?) -> String {
        guard let date else { return "-" }
        return dateFormatter.string(from: date)
    }
}

private struct FinderFileIconView: View {
    let item: FileItem
    let size: CGFloat

    var body: some View {
        #if os(macOS)
        Image(nsImage: iconImage())
            .resizable()
            .frame(width: size, height: size)
        #else
        Image(systemName: item.type == .file ? "document" : "folder")
            .font(.system(size: size * 0.7))
        #endif
    }

    #if os(macOS)
    private func iconImage() -> NSImage {
        let icon = NSWorkspace.shared.icon(forFileType: fileTypeIdentifier())
        icon.size = NSSize(width: size, height: size)
        return icon
    }

    private func fileTypeIdentifier() -> String {
        switch item.type {
        case .directory, .uploads, .dropbox:
            return UTType.folder.identifier
        case .file:
            let ext = (item.name as NSString).pathExtension
            if ext.isEmpty {
                return UTType.data.identifier
            }
            return ext
        }
    }
    #endif
}
