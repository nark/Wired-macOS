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
    
    var connectionID: UUID
    var name: String

    private var unreadCount: Int {
        connectionController.runtime(for: connectionID)?.totalUnreadNotifications ?? 0
    }

    private var iconColor: Color {
        if let runtime = connectionController.runtime(for: connectionID) {
            if runtime.status == .connecting || runtime.isAutoReconnectScheduled {
                return .orange
            }

            if runtime.status == .connected {
                return .green
            }
        }

        if connectionController.hasConnectionIssue(connectionID) {
            return .red
        }

        return .blue
    }

    var body: some View {
        let _ = connectionController.connectionIssueRevision
        let _ = connectionController.notificationsRevision

        HStack {
            Image(systemName: "network")
                .foregroundStyle(iconColor)

            Text(name)
            
            Spacer()

            if unreadCount > 0 {
                Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentColor))
            }
        }
    }
}
