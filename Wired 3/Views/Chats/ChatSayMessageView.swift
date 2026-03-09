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
    
    var message: ChatEvent
    var showNickname: Bool = true
    var showAvatar: Bool = true
    var isGroupedWithNext: Bool = false
    
    var body: some View {
        let isFromYou = message.user.id == runtime.userID
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
                    Text(message.text.attributedWithDetectedLinks(linkColor: .white))
                        .messageBubbleStyle(isFromYou: isFromYou)
                }
                .padding(.bottom, isGroupedWithNext ? 2 : 10)
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
                    Text(message.text.attributedWithDetectedLinks(linkColor: .blue))
                        .messageBubbleStyle(isFromYou: isFromYou)
                }
                .padding(.bottom, isGroupedWithNext ? 2 : 10)
                Spacer()
            }
        }
        .listRowSeparator(.hidden)
        .id(message.id)
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
