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
    
    var message: ChatEvent
    
    var body: some View {
        HStack(alignment: .bottom) {
            Text("**\(message.user.nick)** \(message.text)")
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .foregroundStyle(.gray)
                .font(.caption)
            
            Text(message.date, style: .relative)
                .foregroundStyle(.gray)
                .font(.caption)
        }
        .listRowSeparator(.hidden)
        .id(message.id)
    }
}
