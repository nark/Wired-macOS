//
//  ChatsView.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 19/12/2025.
//  Copyright © 2025 Read-Write. All rights reserved.
//

import SwiftUI
import WiredSwift

enum MainTab: Hashable {
    case chats, messages, boards, files, settings, infos
}

struct TabsView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(ConnectionController.self) private var connectionController
    @EnvironmentObject private var transfers: TransferManager
    @StateObject private var filesViewModel = FilesViewModel.empty()
    
    @State var bookmark: Bookmark
    @State var askDisconnect = false
    
    var body: some View {
#if os(macOS)
        VStack {
            if let runtime = connectionController.runtime(for: bookmark.id) {
                @Bindable var runtime = runtime
                
                VStack {
                    if runtime.status == .connected {
                        if runtime.joined {
                            switch runtime.selectedTab {
                            case .chats:
                                ChatsView(bookmark: bookmark)
                                    .environment(connectionController)
                                    .environment(runtime)
                            case .messages:
                                Text("Messages")
                            case .boards:
                                Text("Boards")
                            case .files:
                                FilesView(bookmark: bookmark, filesViewModel: filesViewModel)
                                    .environment(connectionController)
                                    .environmentObject(transfers)
                                    .environment(runtime)
                            case .settings:
                                ServerSettingsView(bookmark: bookmark)
                                    .environment(connectionController)
                                    .environment(runtime)
                            case .infos:
                                ServerInfoView(bookmark: bookmark)
                                    .environment(connectionController)
                                    .environment(runtime)
                            }
                        } else {
                            ProgressView()
                            Text("Connecting…")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .padding(.top, 5)
                        }
                    }
                    else {
                        Image(systemName: "cable.connector.slash")
                            .font(.system(size: 72))
                            .foregroundColor(.gray)
                            .padding(10)
                        
                        Text("Disconnected")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 5)
                            .padding(.bottom, 5)
                            .foregroundColor(.gray)
                        
                        Button("Connect") {
                            connectionController.connect(bookmark)
                        }
                    }
                }
                .errorAlert(error: $runtime.lastError)
                .task(id: "\(runtime.status)-\(runtime.joined)-\(bookmark.id.uuidString)") {
                    guard runtime.status == .connected, runtime.joined else { return }
                    filesViewModel.configure(
                        fileService: FileService(),
                        runtime: runtime
                    )

                    if filesViewModel.columns.isEmpty {
                        await filesViewModel.loadRoot()
                    } else {
                        await filesViewModel.reloadAll()
                    }
                }
            }
        }
        .task {
            self.connect()
        }
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            if let runtime = connectionController.runtime(for: bookmark.id) {
                ToolbarItemGroup(placement: .navigation) {
                    if let serverInfo = runtime.connection?.serverInfo {
                        Image(data: serverInfo.serverBanner)
                    }
                }
                
                ToolbarItemGroup(placement: .principal) {
                    Button {
                        runtime.selectedTab = .chats
                    } label: {
                        VStack {
                            Image(systemName: "text.bubble")
                                .frame(minHeight: 18)
                            
                            Text("Chats")
                                .font(.subheadline)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(runtime.selectedTab == .chats ? .accentColor : .primary)
                    
                    Button {
                        runtime.selectedTab = .messages
                    } label: {
                        VStack {
                            Image(systemName: "ellipsis.message")
                                .frame(minHeight: 18)
                            
                            Text("Messages").font(.subheadline)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(runtime.selectedTab == .messages ? .accentColor : .primary)
                    
                    Button {
                        runtime.selectedTab = .boards
                    } label: {
                        VStack {
                            Image(systemName: "newspaper")
                                .frame(minHeight: 18)
                            
                            Text("Boards").font(.subheadline)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(runtime.selectedTab == .boards ? .accentColor : .primary)
                    
                    Button {
                        runtime.selectedTab = .files
                    } label: {
                        VStack {
                            Image(systemName: "folder")
                                .frame(minHeight: 18)
                            
                            Text("Files").font(.subheadline)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(runtime.selectedTab == .files ? .accentColor : .primary)
                    
                    Button {
                        runtime.selectedTab = .settings
                    } label: {
                        VStack {
                            Image(systemName: "gear")
                                .frame(minHeight: 18)
                            
                            Text("Settings").font(.subheadline)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(runtime.selectedTab == .settings ? .accentColor : .primary)
                    
                    Button {
                        runtime.selectedTab = .infos
                    } label: {
                        VStack {
                            Image(systemName: "info.circle")
                                .frame(minHeight: 18)
                            
                            Text("Info").font(.subheadline)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(runtime.selectedTab == .infos ? .accentColor : .primary)
                }
                
                ToolbarItemGroup(placement: .automatic) {
                    if runtime.status == .connected {
                        Button {
                            askDisconnect = true
                        } label: {
                            VStack {
                                Image(systemName: "xmark.circle")
                                    .frame(minHeight: 18)
                                
                                Text("Disconnect").font(.subheadline)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(runtime.status == .connecting)
                        .modifier(
                            DisconnectAlert(bookmark: bookmark, askDisconnect: $askDisconnect, onConfirm: {
                                connectionController.disconnect(bookmark, runtime: runtime)
                                dismiss()
                            })
                        )
                        
                    } else {
                        Button {
                            connectionController.connect(bookmark)
                        } label: {
                            VStack {
                                Image(systemName: "arrow.clockwise")
                                Text("Connect")
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(runtime.status == .connecting)
                    }
                }
            }
        }
#elseif os(iOS)
        VStack {
            if let runtime = connectionController.runtime(for: bookmark.id) {
                @Bindable var runtime = runtime
                
                TabView {
                    Tab("Chat", systemImage: "text.bubble.fill") {
                        ChatsView(bookmark: bookmark)
                            .environment(connectionController)
                            .environment(runtime)
                            .navigationTitle(bookmark.name)
                    }
                    
                    Tab("Messages", systemImage: "ellipsis.message.fill") {
                        Text("Messages")
                    }
                    
                    Tab("Boards", systemImage: "newspaper.fill") {
                        Text("Boards")
                    }
                    
                    Tab("Files", systemImage: "folder.fill") {
                        Text("Files")
                    }
                    
                    Tab("Settings", systemImage: "gearshape.fill") {
                        Text("Settings")
                    }
                    
                    Tab("Info", systemImage: "info.circle.fill") {
                        ServerInfoView(bookmark: bookmark)
                            .environment(connectionController)
                            .environment(runtime)
                            .navigationTitle(bookmark.name)
                    }
                }
                .navigationTitle("")
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        if let serverInfo = runtime.connection?.serverInfo {
                            Image(data: serverInfo.serverBanner)
                        }
                    }
                    
                    ToolbarItem(placement: .topBarTrailing) {
                        if runtime.status == .connected {
                            Button {
                                askDisconnect = true
                            } label: {
                                VStack {
                                    Image(systemName: "rectangle.portrait.and.arrow.right")
                                }
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.red)
                            .disabled(runtime.status == .connecting)
                            .modifier(
                                DisconnectAlert(bookmark: bookmark, askDisconnect: $askDisconnect, onConfirm: {
                                    connectionController.disconnect(bookmark, runtime: runtime)
                                    dismiss()
                                })
                            )
                        }
                    }
                }
                .errorAlert(error: $runtime.lastError)
            }
        }
        .task {
            self.connect()
        }
#endif
//        Text(bookmark.id.uuidString)
//            .task {
//                self.connect()
//            }
//        
//        if connectionController.isConnected(bookmark) {
//            Button {
//                connectionController.disconnect(bookmark)
//            } label: {
//                Text("Disconnect")
//            }
//            
//            ForEach(connectionController.runtimeStore.chatsByConnection[bookmark.id] ?? []) { chat in
//                Text(chat.name)
//            }
//        } else {
//            Button(action: connect) {
//                Text("Connect")
//            }
//        }
//
//        if let error = connectionController.runtimeStore.states[bookmark.id]?.lastError as? WiredError {
//            let _ = print("error \(error)")
//            Text("\(error.message)")
//        }
    }
    
    func connect() {
        connectionController.connect(bookmark)
    }
}


struct DisconnectAlert: ViewModifier {
    var bookmark: Bookmark
    @Binding var askDisconnect: Bool
    
    let onConfirm: () -> Void
    
    func body(content: Content) -> some View {
        content
            .alert("Disconnect", isPresented: $askDisconnect) {
                Button("OK", role: .destructive) {
                    onConfirm()
                }
                
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to disconnect from this server?")
            }
    }
}
