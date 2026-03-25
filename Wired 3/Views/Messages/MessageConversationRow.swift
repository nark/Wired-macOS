//
//  MessageConversationRow.swift
//  Wired 3
//

import SwiftUI

struct MessageConversationRow: View {
    @Environment(ConnectionRuntime.self) private var runtime
    let conversation: MessageConversation
    var searchText: String = ""

    private var previewText: String? {
        conversation.previewText(matching: searchText)
    }

    var body: some View {
        HStack {
            avatar

            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.title)
                    .lineLimit(1)

                if let body = previewText, !body.isEmpty {
                    Text(body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                if let lastMessageDate = conversation.lastMessageDate {
                    RelativeDateText(date: lastMessageDate)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if conversation.unreadMessagesCount > 0 {
                    Text("\(conversation.unreadMessagesCount)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.accentColor))
                }
            }
        }
    }

    @ViewBuilder
    private var avatar: some View {
        switch conversation.kind {
        case .broadcast:
            Image(systemName: "megaphone.fill")
                .frame(width: 32, height: 32)
                .foregroundStyle(.secondary)
        case .direct:
            if let icon = runtime.messageConversationIcon(for: conversation),
               let image = Image(data: icon) {
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
}
