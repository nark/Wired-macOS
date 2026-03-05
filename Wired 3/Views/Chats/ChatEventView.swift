//
//  ChatMessageView.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 25/12/2025.
//  Copyright © 2025 Read-Write. All rights reserved.
//

import SwiftUI

struct ChatEventView: View {
    @Environment(ConnectionRuntime.self) private var runtime
    
    var message: ChatEvent
    
    var body: some View {
        HStack(alignment: .bottom) {
            if message.type == .join {
                Text("**\(message.user.nick)** joined")
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.gray)
                    .font(.caption)
            } else if message.type == .leave {
                Text("**\(message.user.nick)** left")
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.gray)
                    .font(.caption)
            } else if message.type == .event {
                Text(message.text)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.gray)
                    .font(.caption)
            }
        }
        .listRowSeparator(.hidden)
        .id(message.id)
    }
}
