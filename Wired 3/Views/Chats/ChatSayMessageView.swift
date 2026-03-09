//
//  ChatMessageView.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 25/12/2025.
//  Copyright © 2025 Read-Write. All rights reserved.
//

import SwiftUI

struct ChatSayMessageView: View {
    @Environment(ConnectionRuntime.self) private var runtime
    @AppStorageCodable(key: "ChatHighlightRules", defaultValue: [])
    private var highlightRules: [ChatHighlightRule]
    
    var message: ChatEvent
    var showNickname: Bool = true
    var showAvatar: Bool = true
    var isGroupedWithNext: Bool = false
    
    var body: some View {
        let isFromYou = message.user.id == runtime.userID
        let matchedRule = matchedHighlightRule(in: message.text)
        let bubbleFillColor = matchedRule?.color.swiftUIColor
        let bubbleTextColor = matchedRule?.color.contrastTextColor
        let linkColor = bubbleTextColor ?? (isFromYou ? .white : .blue)

        HStack(alignment: .bottom) {
            if isFromYou {
                Spacer()
                VStack(alignment: .trailing) {
                    if showNickname {
                        Text(message.user.nick)
                            .font(.caption)
                            .foregroundStyle(.gray)
                            .padding(.trailing, 10)
                    }
                    Text(message.text.attributedWithDetectedLinks(linkColor: linkColor))
                        .messageBubbleStyle(
                            isFromYou: isFromYou,
                            customFillColor: bubbleFillColor,
                            customForegroundColor: bubbleTextColor
                        )
                }
                .padding(.bottom, isGroupedWithNext ? 2 : 8)
                avatarView
            } else {
                avatarView
                VStack(alignment: .leading) {
                    if showNickname {
                        Text(message.user.nick)
                            .font(.caption)
                            .foregroundStyle(.gray)
                            .padding(.leading, 10)
                    }
                    Text(message.text.attributedWithDetectedLinks(linkColor: linkColor))
                        .messageBubbleStyle(
                            isFromYou: isFromYou,
                            customFillColor: bubbleFillColor,
                            customForegroundColor: bubbleTextColor
                        )
                }
                .padding(.bottom, isGroupedWithNext ? 2 : 8)
                Spacer()
            }
        }
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        .id(message.id)
    }

    private func matchedHighlightRule(in text: String) -> ChatHighlightRule? {
        let loweredText = text.lowercased()
        return highlightRules.first { rule in
            let keyword = rule.keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !keyword.isEmpty else { return false }
            return loweredText.contains(keyword)
        }
    }

    @ViewBuilder
    private var avatarView: some View {
        if showAvatar {
            if let icon = Image(data: message.user.icon) {
                icon
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
