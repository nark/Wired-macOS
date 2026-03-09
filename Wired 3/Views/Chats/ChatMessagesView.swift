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
                ForEach(Array(chat.messages.enumerated()), id: \.element.id) { index, message in
                    if message.type == .say {
                        let previous = index > 0 ? chat.messages[index - 1] : nil
                        let next = index < (chat.messages.count - 1) ? chat.messages[index + 1] : nil
                        let sameAsPrevious = previous?.type == .say && previous?.user.id == message.user.id
                        let sameAsNext = next?.type == .say && next?.user.id == message.user.id

                        ChatSayMessageView(
                            message: message,
                            showNickname: !sameAsPrevious,
                            showAvatar: !sameAsNext,
                            isGroupedWithNext: sameAsNext
                        )
                            .environment(runtime)
                    }
                    else if message.type == .me {
                        ChatMeMessageView(message: message)
                            .environment(runtime)
                    }
                    else if message.type == .join || message.type == .leave || message.type == .event {
                        ChatEventView(message: message)
                            .environment(runtime)
                    }
                }
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 1)
            .textSelection(.enabled)
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
