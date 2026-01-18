//
//  ChatView.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 24/12/2025.
//  Copyright © 2025 Read-Write. All rights reserved.
//

import SwiftUI

struct ChatView: View {
    @Environment(ConnectionRuntime.self) private var runtime
    
    var chat: Chat
    
    @State private var chatInput: String = ""
    @FocusState private var isFocused: Bool
    
    @AppStorage("SubstituteEmoji") var substituteEmoji: Bool = true
    @AppStorageCodable(key: "EmojiSubstitutions", defaultValue: [
        ":-)": "😊",
        ":)":  "😊",
        ";-)": "😉",
        ";)":  "😉",
        ":-D": "😀",
        ":D":  "😀",
        "<3":  "❤️",
        "+1":  "👍"
    ])
    var emojiSubstitutions: [String: String]
    
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                ChatTopicView(chat: chat)
                    .environment(runtime)
                
                Divider()
                
                ChatMessagesView(chat: chat)
                    .environment(runtime)
                
                Divider()
                
                TextField("", text: $chatInput)
                    .textFieldStyle(.roundedBorder)
                    .padding(5)
                    .focused($isFocused)
                    .onAppear {
                        isFocused = true
                    }
                    .onSubmit {
                        Task {
                            await sendMessage()
                        }
                    }
            }
#if os(macOS)
            Divider()
            
            if let chatID = runtime.selectedChatID,
               let chat = runtime.chats.first(where: { $0.id == chatID })
            {
                ChatUsersList(chat: chat)
                    .environment(runtime)
            }
#endif
        }
        .onAppear {
            runtime.resetUnreads(chat)
            
#if os(iOS)
            if chat.joined == false {
                Task {
                    try? await runtime.joinChat(chat.id)
                }
            }
#endif
        }
        .toolbar {
#if os(iOS)
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    ChatUsersList(chat: chat)
                        .environment(runtime)
                        .navigationTitle("Users")
                } label: {
                    Image(systemName: "person.2.fill")
                }

            }
            
#endif
        }
    }
    
    func sendMessage() async {
        do {
            if substituteEmoji {
                chatInput = chatInput.replacingEmoticons(using: emojiSubstitutions)
            }
            
            if let _ = try await runtime.sendChatMessage(chat.id, chatInput) {
                chatInput = ""
            }
        } catch {
            runtime.lastError = error
        }
    }
}
