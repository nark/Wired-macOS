//
//  FileInfoSheet.swift
//  Wired 3
//
//  Created by Codex on 18/02/2026.
//

import SwiftUI

struct FileInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ConnectionRuntime.self) private var runtime

    @ObservedObject var filesViewModel: FilesViewModel
    let file: FileItem

    @State private var selectedTypeRawValue: UInt32
    @State private var isSaving = false

    init(filesViewModel: FilesViewModel, file: FileItem) {
        self.filesViewModel = filesViewModel
        self.file = file
        _selectedTypeRawValue = State(initialValue: file.type.rawValue)
    }

    private var selectedType: FileType {
        FileType(rawValue: selectedTypeRawValue) ?? .directory
    }

    private var isDirectoryType: Bool {
        file.type == .directory || file.type == .uploads || file.type == .dropbox
    }

    private var canEditType: Bool {
        isDirectoryType && runtime.hasPrivilege("wired.account.file.set_type")
    }

    private var hasChanges: Bool {
        selectedTypeRawValue != file.type.rawValue
    }

    var body: some View {
        NavigationStack {
            Form {
                LabeledContent("Path", value: file.path)
                LabeledContent("Current Type", value: file.type.description)

                Picker("Type", selection: $selectedTypeRawValue) {
                    ForEach([FileType.directory, FileType.uploads, FileType.dropbox], id: \.rawValue) { type in
                        Text(type.description).tag(type.rawValue)
                    }
                }
                .disabled(!canEditType)
            }
            .navigationTitle("File Info")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await save()
                        }
                    }
                    .disabled(!canEditType || !hasChanges || isSaving)
                }
            }
        }
    }

    @MainActor
    private func save() async {
        guard canEditType, hasChanges else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            try await filesViewModel.setFileType(path: file.path, type: selectedType)
            dismiss()
        } catch {
            filesViewModel.error = error
        }
    }
}

