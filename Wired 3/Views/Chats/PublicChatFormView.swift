//
//  PublicChatFormView.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 04/01/2026.
//  Copyright © 2026 Read-Write. All rights reserved.
//

import SwiftUI
import WiredSwift

struct PublicChatFormView: View {
    @Environment(ConnectionRuntime.self) private var runtime
    @Environment(\.dismiss) var dismiss
    
    @State var chat: Chat?
    @State var chatName: String = ""
    
    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $chatName)
            }
            .padding()
            .formStyle(.columns)
            .navigationTitle("Create Public Chat")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel")
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            await save()
                        }
                    } label: {
                        Text("OK")
                    }
                }
            }
            .onAppear {
                if let chat {
                    chatName = chat.name
                }
            }
        }
    }
    
    func save() async {
        if chatName != "" {
            let message = P7Message(withName: "wired.chat.create_public_chat", spec: spec!)
            message.addParameter(field: "wired.chat.name", value: chatName)
            
            do {
                try await runtime.send(message)
                
                dismiss()
                
            } catch {
                
            }
        }
    }
}
