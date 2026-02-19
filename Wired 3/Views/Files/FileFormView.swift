//
//  FolderFormView.swift
//  Wired-macOS
//
//  Created by Rafaël Warnault on 16/01/2026.
//  Copyright © 2026 Read-Write. All rights reserved.
//

import SwiftUI
import WiredSwift

struct FileFormView: View {
    @Environment(\.dismiss) var dismiss
    
    @Environment(ConnectionRuntime.self) private var runtime
    @ObservedObject var filesViewModel: FilesViewModel
    
    @State private var fileName = ""
    @State private var fileType: UInt32 = FileType.directory.rawValue
    @State private var isSaving = false
    
    var parentDirectory: FileItem
    var file: FileItem?
    
    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $fileName)
                
                if runtime.hasPrivilege("wired.account.file.set_type") {
                    Picker("Type", selection: $fileType) {
                        ForEach([
                            FileType.directory,
                            FileType.uploads,
                            FileType.dropbox
                        ], id: \.rawValue) { c in
                            Text(c.description).tag(c.rawValue)
                        }
                    }
                }
            }
            .navigationTitle("Create Directory")
            .formStyle(.grouped)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel, action: {
                        dismiss()
                    })
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        Task {
                            await save()
                        }
                    }
                    .disabled(fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }
        .onAppear {
            if let file {
                fileName = file.name
            }
        }
    }
    
    func save() async {
        isSaving = true
        defer { isSaving = false }

        let selectedType = FileType(rawValue: fileType) ?? .directory
        let effectiveType: FileType = runtime.hasPrivilege("wired.account.file.set_type")
            ? selectedType
            : .directory

        let created = await filesViewModel.createDirectory(
            name: fileName,
            in: parentDirectory,
            type: effectiveType
        )
        if created {
            dismiss()
        }
    }
}
