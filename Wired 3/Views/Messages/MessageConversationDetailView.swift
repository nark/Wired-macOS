//
//  MessageConversationDetailView.swift
//  Wired 3
//

import SwiftUI

struct MessageConversationDetailView: View {
    @Environment(ConnectionRuntime.self) private var runtime

    let conversation: MessageConversation
    @State private var inputText: String = ""

    private var canSend: Bool {
        runtime.canSendMessage(to: conversation)
    }

    private var placeholder: String {
        if conversation.kind == .broadcast {
            return "Broadcast to all online users…"
        }
        return canSend ? "Type message here…" : "User unavailable"
    }

    var body: some View {
        VStack(spacing: 0) {
            MessageConversationMessagesView(conversation: conversation)
                .environment(runtime)

            Divider()

            ConversationComposer(
                text: $inputText,
                placeholder: placeholder,
                isEnabled: canSend,
                onSend: { text in
                    do {
                        switch conversation.kind {
                        case .direct:
                            try await runtime.sendPrivateMessage(text, in: conversation)
                        case .broadcast:
                            try await runtime.sendBroadcastMessage(text)
                        }
                    } catch {
                        runtime.lastError = error
                    }
                }
            )
        }
        .onAppear {
            runtime.resetUnreads(conversation)
        }
    }
}
