//
//  FilesView.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 09/01/2026.
//  Copyright © 2026 Read-Write. All rights reserved.
//

import SwiftUI
import WiredSwift

struct FilesView: View {
    @Environment(ConnectionController.self) private var connectionController
    @Environment(ConnectionRuntime.self) private var runtime
    @EnvironmentObject private var transfers: TransferManager
        
    var bookmark: Bookmark
    
    @ObservedObject var filesViewModel:FilesViewModel
    
    @State private var selectedFileViewType: FileViewType = .columns
    @State private var selectedFile: URL?
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $selectedFileViewType) {
                    Image(systemName: "list.bullet.indent").tag(FileViewType.tree)
                    Image(systemName: "rectangle.split.3x1").tag(FileViewType.columns)
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 80)
                
                Button {
                    if let selectedFile = filesViewModel.selectedItem {
                        if selectedFile.type == .file {
                            transfers.download(selectedFile, with: bookmark.id)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.down")
                }
                .disabled(filesViewModel.selectedItem == nil || filesViewModel.selectedItem?.type != .file)
                
                
                Button {
                    filesViewModel.showFilesBrowser = true
                    
                } label: {
                    Image(systemName: "arrow.up")
                }
                .disabled(filesViewModel.selectedItem == nil)
                
                
                Button {
                    filesViewModel.showCreateFolderSheet = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .disabled(filesViewModel.selectedItem == nil)
                
                
                Button {
                    filesViewModel.showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(filesViewModel.selectedItem == nil || filesViewModel.selectedItem?.path == "/")
                
                
                Spacer()
            }
            .padding()
            
            Divider()
            
            switch selectedFileViewType {
            case .tree:
                FilesTreeView(bookmark: bookmark)
                    .environment(connectionController)
                    .environment(runtime)
                    .environmentObject(transfers)
            case .columns:
                FilesColumnsView(bookmark: bookmark, filesViewModel: filesViewModel)
                    .environment(connectionController)
                    .environment(runtime)
                    .environmentObject(transfers)
            }
        }
        .fileImporter(
            isPresented: $filesViewModel.showFilesBrowser,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                selectedFile = urls.first
                
                if let selectedFile {
                    fileImporterSuccess(selectedFile)
                }
                
            case .failure(let error):
                print("Erreur:", error)
            }
        }
        .sheet(isPresented: $filesViewModel.showCreateFolderSheet) {
            if let selectedFile = filesViewModel.selectedItem {
                if  selectedFile.type == .directory ||
                    selectedFile.type == .uploads ||
                    selectedFile.type == .dropbox
                {
                    FileFormView(filesViewModel: filesViewModel, parentDirectory: selectedFile)
                        .environment(connectionController)
                        .environment(runtime)
                }
            }
        }
        .alert("Delete File", isPresented: $filesViewModel.showDeleteConfirmation, actions: {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let selectedFile = filesViewModel.selectedItem {
                    Task {
                        await filesViewModel.deleteFile(selectedFile.path)
                        await filesViewModel.reloadSelectedColumn()
                    }
                }
            }
        }, message: {
            Text("Are you sure you want to delete this file? This operation is not recoverable.")
        })
        .disabled(filesViewModel.selectedItem == nil)
        
        .errorAlert(error: $filesViewModel.error)
    }
    
    func fileImporterSuccess(_ url: URL) {
        _ = url.startAccessingSecurityScopedResource()

        if var selectedDir = filesViewModel.selectedItem {
            if selectedDir.type == .directory {
                _ = transfers.upload(url.path, toDirectory: selectedDir, with: bookmark.id, filesViewModel: filesViewModel)
            } else {
                let parentPath = selectedDir.path.stringByDeletingLastPathComponent
                selectedDir = FileItem(parentPath.lastPathComponent, path: selectedDir.path.stringByDeletingLastPathComponent)
                
                _ = transfers.upload(url.path, toDirectory: selectedDir, with: bookmark.id, filesViewModel: filesViewModel)
            }
        }
    }
}


struct FilesTreeView: View {
    @Environment(ConnectionController.self) private var connectionController
    @Environment(ConnectionRuntime.self) private var runtime
    @State var bookmark: Bookmark
    
    var body: some View {
        List {
            
        }
    }
}

struct FilesColumnsView: View {
    @Environment(ConnectionController.self) private var connectionController
    @Environment(ConnectionRuntime.self) private var runtime
    @State var bookmark: Bookmark
    
    @ObservedObject var filesViewModel: FilesViewModel
    @EnvironmentObject private var transfers: TransferManager
        
    var body: some View {
        ScrollView(.horizontal) {
            ScrollViewReader { proxy in
                HStack(spacing: 0) {
                    ForEach(Array(filesViewModel.columns.enumerated()), id: \.element.id) { index, column in
                        List(
                            column.items,
                            selection: filesViewModel.selectionBinding(
                                column: index,
                                onColumnAppended: { column in
                                    proxy.scrollTo(column.id, anchor: .trailing)
                                }
                            )
                        ) { item in
                            HStack {
                                Image(systemName: item.type == .directory ? "folder.fill" : "document.fill")
                                    .foregroundStyle(item.type == .directory ? .blue : .primary)

                                Text(item.name)
                                    .lineLimit(1)
                            }
                        }
                        .frame(width: 220)
                        .background(column.selection != nil ? Color.gray.opacity(0.2) : .clear)
                        .id(column.id)
                        .contextMenu(forSelectionType: FileItem.ID.self) { selectedItems in

                        } primaryAction: { selectedItems in
                            if let selectedID = selectedItems.first {
                                if let item = column.items.first(where: { $0.id == selectedID }) {
                                    transfers.download(item, with: bookmark.id)
                                }
                            }
                        }

                        Divider()
                    }
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
}
