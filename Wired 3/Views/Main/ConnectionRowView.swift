//
//  ConnectionRowView.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 19/12/2025.
//  Copyright © 2025 Read-Write. All rights reserved.
//

import SwiftUI

struct ConnectionRowView: View {
    @Environment(ConnectionController.self) private var connectionController
    
    var bookmark: Bookmark

    var body: some View {
        HStack {
            Image(systemName: "network")
                .foregroundStyle(connectionController.runtime(for: bookmark.id)?.status == .connected ? Color.green : Color.blue)

            Text(bookmark.name)
            
            Spacer()
        }
        .badge(connectionController.runtime(for: bookmark.id)?.totalUnreadMessages ?? 0)
    }
}
