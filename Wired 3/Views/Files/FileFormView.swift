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
    
    @Environment(ConnectionController.self) private var connectionController
    @Environment(ConnectionRuntime.self) private var runtime
    @ObservedObject var filesViewModel: FilesViewModel
    
    @State private var fileName = ""
    @State private var fileType: UInt32 = FileType.directory.rawValue
    
    var parentDirectory: FileItem
    var file: FileItem?
    
    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $fileType) {
                    ForEach([
                        FileType.directory,
                        FileType.uploads,
                        FileType.dropbox
                    ], id: \.rawValue) { c in
                        Text(c.description).tag(c.rawValue)
                    }
                }
                TextField("Name", text: $fileName)
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
        let message = P7Message(withName: "wired.file.create_directory", spec: spec!)
        let path = parentDirectory.path + "/" + fileName
        
        message.addParameter(field: "wired.file.path", value: path)
        message.addParameter(field: "wired.file.type", value: fileType)
        
        do {
            let response = try await runtime.send(message)
            
            dismiss()
            
            if response?.name == "wired.error" {
                //throw WiredError(message: response!)
            }
        } catch {
            
        }
    }
}
