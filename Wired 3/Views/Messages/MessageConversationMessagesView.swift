//
//  MessageConversationMessagesView.swift
//  Wired 3
//

import SwiftUI

struct MessageConversationMessagesView: View {
    @Environment(ConnectionRuntime.self) private var runtime
    let conversation: MessageConversation

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(conversation.messages) { message in
                    MessageBubbleRow(message: message, currentUserID: runtime.userID)
                        .id(message.id)
                }
            }
            .listStyle(.plain)
            .textSelection(.enabled)
            .frame(maxHeight: .infinity)
            .onChange(of: conversation.messages.count) {
                DispatchQueue.main.async {
                    if let lastID = conversation.messages.last?.id {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
            .onAppear {
                DispatchQueue.main.async {
                    if let lastID = conversation.messages.last?.id {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
    }
}

private struct MessageBubbleRow: View {
    let message: MessageEvent
    let currentUserID: UInt32

    var body: some View {
        let isFromYou = message.isFromCurrentUser || message.senderUserID == currentUserID
        HStack(alignment: .bottom) {
            if isFromYou {
                Spacer()
                VStack(alignment: .trailing) {
                    Text(message.senderNick)
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .padding(.trailing, 10)
                    Text(message.text.attributedWithDetectedLinks(linkColor: .white))
                        .messageBubbleStyle(isFromYou: true)
                }
                .padding(.bottom, 10)
                avatarView
            } else {
                avatarView
                VStack(alignment: .leading) {
                    Text(message.senderNick)
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .padding(.leading, 10)
                    Text(message.text.attributedWithDetectedLinks(linkColor: .blue))
                        .messageBubbleStyle(isFromYou: false)
                }
                .padding(.bottom, 10)
                Spacer()
            }
        }
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private var avatarView: some View {
        if let icon = message.senderIcon, let image = Image(data: icon) {
            image
                .resizable()
                .frame(width: 32, height: 32)
        } else {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .frame(width: 32, height: 32)
                .foregroundStyle(.secondary)
        }
    }
}
