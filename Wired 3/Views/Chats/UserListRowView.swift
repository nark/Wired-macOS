//
//  UserListRowView.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 28/12/2025.
//  Copyright © 2025 Read-Write. All rights reserved.
//

import SwiftUI
import Foundation

struct UserListRowView: View {
    @Environment(ConnectionRuntime.self) private var runtime
    
    var user: User
    var sourceChat: Chat

    @State private var showBanSheet: Bool = false
    @State private var showKickSheet: Bool = false
    @State private var showDisconnectSheet: Bool = false

    private var hasStatus: Bool {
        guard let status = user.status?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return !status.isEmpty
    }

    private var canInviteToPrivateChat: Bool {
        runtime.hasPrivilege("wired.account.chat.create_chats")
        && user.id != runtime.userID
    }

    private var nickColor: Color {
        switch user.color {
        case 0: return .black
        case 1: return .red
        case 2: return .orange
        case 3: return .green
        case 4: return .blue
        case 5: return .purple
        default: return .primary
        }
    }
    
    var body: some View {
        HStack {
            Image(data: user.icon)?.resizable().frame(width: 32, height: 32)
            
            VStack(alignment: .leading) {
                Text(user.nick)
                    .foregroundStyle(nickColor)

                if hasStatus {
                    Text(user.status ?? "")
                        .foregroundStyle(.gray)
                        .font(.caption2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .opacity(user.idle ? 0.6 : 1.0)
        .listRowSeparator(.hidden)
#if os(macOS)
        .onDrag {
            NSItemProvider(object: NSString(string: String(user.id)))
        }
#endif
        .contextMenu {
            Button("Get Infos") {
                runtime.getUserInfo(user.id)
            }
            .disabled(!runtime.hasPrivilege("wired.account.user.get_info"))
            
            Divider()
            
            Button("Send Private Message") {
                
            }
            .disabled(true)
            .disabled(!runtime.hasPrivilege("wired.account.message.send_messages"))

            Button("Invite to Private Chat") {
                Task {
                    do {
                        if sourceChat.isPrivate {
                            try await runtime.inviteUserToPrivateChat(userID: user.id, chatID: sourceChat.id)
                        } else {
                            try await runtime.createPrivateChat(inviting: user.id)
                        }
                    } catch {
                        runtime.lastError = error
                    }
                }
            }
            .disabled(!canInviteToPrivateChat)
            
            Divider()
            
            Button("Kick") {
                showKickSheet.toggle()
            }
            .disabled(!runtime.hasPrivilege("wired.account.chat.kick_users"))
            
            Button("Ban") {
                showBanSheet.toggle()
            }
            .disabled(!runtime.hasPrivilege("wired.account.user.ban_users"))
            
            Divider()
            
            Button("Disconnect") {
                showDisconnectSheet.toggle()
            }
            .disabled(!runtime.hasPrivilege("wired.account.user.disconnect_users"))
        }
        .sheet(isPresented: $showKickSheet) {
            
        }
        .sheet(isPresented: $showBanSheet) {
            
        }
        .sheet(isPresented: $showDisconnectSheet) {
            
        }
    }
    
}


struct UserInfosView: View {
    @Environment(ConnectionRuntime.self) private var runtime
    
    var user: User
    
    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Text(user.nick)
                } label: {
                    Text("Nick")
                }
                
                LabeledContent {
                    Text(user.status ?? "")
                } label: {
                    Text("Status")
                }
            }
            
            Section {
                LabeledContent {
                    Text("\(user.appVersion) (\(user.appBuild))")
                } label: {
                    Text("App version")
                }
                
                LabeledContent {
                    Text(user.osName)
                } label: {
                    Text("OS Name")
                }
                
                LabeledContent {
                    Text(user.osVersion)
                } label: {
                    Text("OS Version")
                }
                
                LabeledContent {
                    Text(user.arch)
                } label: {
                    Text("Arch")
                }
            }
            
            Section {
                LabeledContent {
                    Text(user.login)
                } label: {
                    Text("Login")
                }
                
                LabeledContent {
                    Text(user.ipAddress)
                } label: {
                    Text("IP Address")
                }
                
                LabeledContent {
                    Text(user.host)
                } label: {
                    Text("Hostname")
                }

                LabeledContent {
                    Text("\(user.cipherName)")
                } label: {
                    Text("Cipher")
                }
            }
            
            Section {
                LabeledContent {
                    if let loginTime = user.loginTime {
                        Text(loginTime, style: .timer)
                    }
                } label: {
                    Text("Login Time")
                }
                
                LabeledContent {
                    if let idleTime = user.idleTime {
                        Text(idleTime, style: .timer)
                    }
                } label: {
                    Text("Idle Time")
                }
            }
        }
        .formStyle(.grouped)
    }
}
