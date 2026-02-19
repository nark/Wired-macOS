//
//  ChatUsersList.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 27/12/2025.
//  Copyright © 2025 Read-Write. All rights reserved.
//

import SwiftUI

struct ChatUsersList: View {
    @Environment(ConnectionRuntime.self) private var runtime
    
    var chat: Chat
        
    var body: some View {
        @Bindable var runtime = runtime
        
        List {
            ForEach(chat.users) { user in
                UserListRowView(user: user, sourceChat: chat)
                    .environment(runtime)
            }
        }
        .popover(isPresented: $runtime.showInfos) {
            if let user = chat.users.first(where: { u in u.id == Int(runtime.showInfosUserID) }) {
                UserInfosView(user: user)
                    .environment(runtime)
            }
        }
        #if os(macOS)
        .frame(width: 200)
        #endif
    }
}
