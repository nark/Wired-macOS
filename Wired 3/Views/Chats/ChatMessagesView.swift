//
//  ChatMessagesView.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 27/12/2025.
//  Copyright © 2025 Read-Write. All rights reserved.
//

import SwiftUI

struct ChatMessagesView: View {
    @Environment(ConnectionRuntime.self) private var runtime
    
    var chat: Chat
    
    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(chat.messages, id: \.id) { message in
                    if message.type == .say {
                        ChatSayMessageView(message: message)
                            .environment(runtime)
                    }
                    else if message.type == .me {
                        ChatMeMessageView(message: message)
                            .environment(runtime)
                    }
                    else if message.type == .join || message.type == .leave {
                        ChatEventView(message: message)
                            .environment(runtime)
                    }
                }
            }
            .listStyle(.plain)
            .frame(maxHeight: .infinity)
            .onChange(of: chat.messages.count) {
                DispatchQueue.main.async {
                    if let lastID = chat.messages.last?.id {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
            .onAppear {
                DispatchQueue.main.async {
                    if let lastID = chat.messages.last?.id {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
    }
}
