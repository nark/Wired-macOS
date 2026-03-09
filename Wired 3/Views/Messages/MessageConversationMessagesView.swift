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
                ForEach(Array(conversation.messages.enumerated()), id: \.element.id) { index, message in
                    let previous = index > 0 ? conversation.messages[index - 1] : nil
                    let next = index < (conversation.messages.count - 1) ? conversation.messages[index + 1] : nil
                    let sameAsPrevious = previous.map { isSameSender($0, as: message) } ?? false
                    let sameAsNext = next.map { isSameSender($0, as: message) } ?? false

                    MessageBubbleRow(
                        message: message,
                        currentUserID: runtime.userID,
                        showNickname: !sameAsPrevious,
                        showAvatar: !sameAsNext,
                        isGroupedWithNext: sameAsNext
                    )
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

    private func senderKey(for message: MessageEvent) -> String {
        if message.isFromCurrentUser || message.senderUserID == runtime.userID {
            return "me"
        }
        if let senderUserID = message.senderUserID {
            return "id:\(senderUserID)"
        }
        return "nick:\(message.senderNick)"
    }

    private func isSameSender(_ lhs: MessageEvent, as rhs: MessageEvent) -> Bool {
        senderKey(for: lhs) == senderKey(for: rhs)
    }
}

private struct MessageBubbleRow: View {
    let message: MessageEvent
    let currentUserID: UInt32
    let showNickname: Bool
    let showAvatar: Bool
    let isGroupedWithNext: Bool

    var body: some View {
        let isFromYou = message.isFromCurrentUser || message.senderUserID == currentUserID
        HStack(alignment: .bottom) {
            if isFromYou {
                Spacer()
                VStack(alignment: .trailing) {
                    if showNickname {
                        Text(message.senderNick)
                            .font(.caption)
                            .foregroundStyle(.gray)
                            .padding(.trailing, 10)
                    }
                    Text(message.text.attributedWithDetectedLinks(linkColor: .white))
                        .messageBubbleStyle(isFromYou: true)
                }
                .padding(.bottom, isGroupedWithNext ? 2 : 10)
                avatarView
            } else {
                avatarView
                VStack(alignment: .leading) {
                    if showNickname {
                        Text(message.senderNick)
                            .font(.caption)
                            .foregroundStyle(.gray)
                            .padding(.leading, 10)
                    }
                    Text(message.text.attributedWithDetectedLinks(linkColor: .blue))
                        .messageBubbleStyle(isFromYou: false)
                }
                .padding(.bottom, isGroupedWithNext ? 2 : 10)
                Spacer()
            }
        }
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private var avatarView: some View {
        if showAvatar {
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
        } else {
            Color.clear
                .frame(width: 32, height: 32)
        }
    }
}
