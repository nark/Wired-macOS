//
//  ChatMessageView.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 25/12/2025.
//  Copyright © 2025 Read-Write. All rights reserved.
//

import SwiftUI

struct ChatMeMessageView: View {
    @Environment(ConnectionRuntime.self) private var runtime
    @AppStorage("TimestampEveryMessage") var timestampEveryMessage: Bool = false
    
    var message: ChatEvent
    
    var body: some View {
        HStack(alignment: .bottom) {
            if timestampEveryMessage {
                RelativeDateText(date: message.date)
                    .foregroundStyle(.clear)
                    .monospacedDigit()
                    .font(.caption)
            }
            
            Spacer()
            
            (
                Text("**\(message.user.nick)** ")
                +
                Text(message.text.attributedWithDetectedLinks(linkColor: .blue))
            )
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .foregroundStyle(.gray)
                .font(.caption)
            
            Spacer()
            
            if timestampEveryMessage {
                HoverableRelativeDateText(date: message.date)
                    .foregroundStyle(.gray)
                    .monospacedDigit()
                    .font(.caption)
            }
        }
        .listRowSeparator(.hidden)
        .id(message.id)
    }
}
