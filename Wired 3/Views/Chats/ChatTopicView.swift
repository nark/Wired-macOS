//
//  ChatTopicView.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 25/12/2025.
//  Copyright © 2025 Read-Write. All rights reserved.
//

import SwiftUI

struct ChatTopicView: View {
    @Environment(ConnectionRuntime.self) private var runtime
    
    var chat: Chat
    
    var body: some View {
        HStack(alignment: .top) {
            Text("**Topic:** \(chat.topic?.topic ?? "")")
                .multilineTextAlignment(.leading)
                .lineLimit(2, reservesSpace: false)
                .help(chat.topic?.topic ?? "")
            
            Spacer()
            
            if let topic = chat.topic {
                VStack(alignment: .trailing) {
                    Text("By *\(topic.nick)*")
                        .font(.footnote)
                        .foregroundStyle(.gray)
                    
                    Text("At *\(topic.time.formatted())*")
                        .font(.footnote)
                        .foregroundStyle(.gray)
                }
            }
        }
        .padding(.top, 1)
        .padding(5)
    }
}
