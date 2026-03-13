//
//  ServerInfoView.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 07/01/2026.
//  Copyright © 2026 Read-Write. All rights reserved.
//

import SwiftUI

struct ServerInfoView: View {
    @Environment(ConnectionRuntime.self) private var runtime
    
    var body: some View {
        Group {
            if let serverInfo = runtime.serverInfo {
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
                        Text("Application Name").bold()
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
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading server information…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .task(id: "\(runtime.status)-\(runtime.selectedTab)") {
            await refreshServerInfoIfNeeded()
        }
    }

    @MainActor
    private func refreshServerInfoIfNeeded() async {
        guard runtime.status == .connected else { return }
        guard runtime.selectedTab == .infos else { return }
        guard runtime.serverInfo == nil else { return }

        if let serverInfo = runtime.connection?.serverInfo {
            runtime.serverInfo = serverInfo
            return
        }

        // Slow or remote servers may expose serverInfo slightly later than first render.
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(250))
            guard runtime.status == .connected, runtime.selectedTab == .infos else { return }
            if runtime.serverInfo != nil { return }
            if let serverInfo = runtime.connection?.serverInfo {
                runtime.serverInfo = serverInfo
                return
            }
        }
    }
}
