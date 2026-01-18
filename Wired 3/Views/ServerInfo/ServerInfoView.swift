//
//  ServerInfoView.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 07/01/2026.
//  Copyright © 2026 Read-Write. All rights reserved.
//

import SwiftUI

struct ServerInfoView: View {
    @Environment(ConnectionController.self) private var connectionController
    @Environment(ConnectionRuntime.self) private var runtime
    @State var bookmark: Bookmark
    
    var body: some View {
        if let serverInfo = runtime.connection?.serverInfo {
            VStack {
                Image(data: serverInfo.serverBanner)
                
                VStack {
                    Text(serverInfo.serverName)
                        .font(.title)
                    
                    Text(serverInfo.serverDescription)
                        .font(.caption)
                }
                
                Divider()
                
                LabeledContent {
                    Text(serverInfo.applicationName)
                } label: {
                    Text("Server Name").bold()
                }
                
                LabeledContent {
                    Text(serverInfo.serverVersion)
                } label: {
                    Text("Server Version").bold()
                }
                
                Divider()

                LabeledContent {
                    Text(serverInfo.osName)
                } label: {
                    Text("OS Name").bold()
                }
                
                LabeledContent {
                    Text(serverInfo.osVersion)
                } label: {
                    Text("OS Version").bold()
                }
                
                LabeledContent {
                    Text(serverInfo.arch)
                } label: {
                    Text("OS Arch").bold()
                }
                
                Divider()
                
                LabeledContent {
                    Text("\(serverInfo.filesCount) files")
                } label: {
                    Text("Files").bold()
                }
                
                LabeledContent {
                    Text("\(ByteCountFormatter().string(fromByteCount: Int64(serverInfo.filesSize)))")
                } label: {
                    Text("Size").bold()
                }
                
                LabeledContent {
                    Text(serverInfo.startTime, style: .timer)
                } label: {
                    Text("Uptime").bold()
                }
            }
            .frame(maxWidth: 400)
        }
    }
}
