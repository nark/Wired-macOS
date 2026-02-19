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
    
    var body: some View {
        let isFromYou = message.user.id == runtime.userID
        HStack(alignment: .bottom) {
            if isFromYou {
                Spacer()
                VStack(alignment: .trailing) {
                    Text(message.user.nick)
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .padding(.trailing, 10)
                    Text(message.text.attributedWithDetectedLinks(linkColor: .white))
                        .messageBubbleStyle(isFromYou: isFromYou)
                }
                .padding(.bottom, 10)
                Image(data: message.user.icon)?.resizable().frame(width: 32, height: 32)
            } else {
                Image(data: message.user.icon)?.resizable().frame(width: 32, height: 32)
                VStack(alignment: .leading) {
                    Text(message.user.nick)
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .padding(.leading, 10)
                    Text(message.text.attributedWithDetectedLinks(linkColor: .blue))
                        .messageBubbleStyle(isFromYou: isFromYou)
                }
                .padding(.bottom, 10)
                Spacer()
            }
        }
        .listRowSeparator(.hidden)
        .id(message.id)
    }
}
