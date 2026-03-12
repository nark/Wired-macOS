//
//  ChatsView.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 19/12/2025.
//  Copyright © 2025 Read-Write. All rights reserved.
//

import SwiftUI
import SwiftData
import KeychainSwift
import WiredSwift

enum MainTab: Hashable {
    case chats, messages, boards, files, settings, infos
}

struct TabsView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ConnectionController.self) private var connectionController
    @EnvironmentObject private var transfers: TransferManager
    @StateObject private var filesViewModel = FilesViewModel.empty()

    let connectionID: UUID
    let connectionName: String
    let bookmark: Bookmark?

    @State private var askDisconnect = false

    private var isBookmarked: Bool {
        bookmark != nil
    }

    private var connectionTitle: String {
        guard let runtime = connectionController.runtime(for: connectionID) else {
            return connectionName
        }

        if runtime.status == .disconnected {
            return "⚠︎ \(connectionName)"
        }

        return connectionName
    }

    var body: some View {
#if os(macOS)
        VStack {
            if let runtime = connectionController.runtime(for: connectionID) {
                @Bindable var runtime = runtime

                VStack {
                    if runtime.status == .connected {
                        if runtime.joined {
                            switch runtime.selectedTab {
                            case .chats:
                                ChatsView()
                                    .environment(connectionController)
                                    .environment(runtime)
                            case .messages:
                                MessagesView()
                                    .environment(runtime)
                            case .boards:
                                BoardsView()
                                    .environment(runtime)
                            case .files:
                                FilesView(connectionID: connectionID, filesViewModel: filesViewModel)
                                    .environment(connectionController)
                                    .environmentObject(transfers)
                                    .environment(runtime)
                            case .settings:
                                ServerSettingsView(connectionID: connectionID)
                                    .environment(connectionController)
                                    .environment(runtime)
                            case .infos:
                                ServerInfoView()
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
                    } else if runtime.status == .connecting {
                        Image(systemName: "cable.connector.slash")
                            .font(.system(size: 72))
                            .foregroundColor(.gray)
                            .padding(10)

                        ProgressView()
                            .padding(.top, 4)

                        Text("Connecting…")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 5)
                            .padding(.bottom, 5)
                            .foregroundColor(.gray)
                    } else {
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
                            connect()
                        }

                        if runtime.isAutoReconnectScheduled {
                            ProgressView()
                                .padding(.top, 6)
                            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                                Text(autoReconnectLabel(for: runtime, now: timeline.date))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.top, 6)
                            }
                        }
                    }
                }
                .errorAlert(
                    error: $runtime.lastError,
                    source: "Connection",
                    serverName: connectionName,
                    connectionID: runtime.id
                )
                .task(id: "\(runtime.status)-\(runtime.joined)-\(connectionID.uuidString)") {
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
        .navigationTitle(connectionTitle)
        .toolbarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbar {
            if let runtime = connectionController.runtime(for: connectionID) {
                ToolbarItemGroup(placement: .navigation) {
                    if let serverInfo = runtime.connection?.serverInfo {
                        Image(data: serverInfo.serverBanner)
                    }
                }
                .sharedBackgroundHiddenIfAvailable()

                ToolbarItemGroup(placement: .principal) {
                    Button {
                        runtime.selectedTab = .chats
                    } label: {
                        VStack {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "text.bubble")
                                    .frame(minHeight: 18)

                                if runtime.totalUnreadChatMessages > 0 {
                                    Text(runtime.totalUnreadChatMessages > 99 ? "99+" : "\(runtime.totalUnreadChatMessages)")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(.red))
                                        .offset(x: 12, y: -8)
                                }
                            }

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
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "ellipsis.message")
                                    .frame(minHeight: 18)

                                if runtime.totalUnreadPrivateMessages > 0 {
                                    Text(runtime.totalUnreadPrivateMessages > 99 ? "99+" : "\(runtime.totalUnreadPrivateMessages)")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(.red))
                                        .offset(x: 12, y: -8)
                                }
                            }

                            Text("Messages").font(.subheadline)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(runtime.selectedTab == .messages ? .accentColor : .primary)

                    Button {
                        runtime.selectedTab = .boards
                    } label: {
                        VStack {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "newspaper")
                                    .frame(minHeight: 18)

                                if runtime.totalUnreadBoardPosts > 0 {
                                    Text(runtime.totalUnreadBoardPosts > 99 ? "99+" : "\(runtime.totalUnreadBoardPosts)")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(.red))
                                        .offset(x: 12, y: -8)
                                }
                            }

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
                .sharedBackgroundHiddenIfAvailable()
                
                ToolbarItemGroup(placement: .automatic) {
                    if !isBookmarked {
                        Button {
                            bookmarkCurrentConnection()
                        } label: {
                            VStack {
                                Image(systemName: "bookmark")
                                    .frame(minHeight: 18)

                                Text("Bookmark").font(.subheadline)
                            }
                        }
                        .buttonStyle(.plain)
                    }

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
                            DisconnectAlert(askDisconnect: $askDisconnect, onConfirm: {
                                connectionController.disconnect(connectionID: connectionID, runtime: runtime)
                                dismiss()
                            })
                        )

                    } else {
                        Button {
                            connect()
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
                .sharedBackgroundHiddenIfAvailable()
            }
        }
#elseif os(iOS)
        VStack {
            if let runtime = connectionController.runtime(for: connectionID) {
                @Bindable var runtime = runtime

                TabView {
                    Tab("Chat", systemImage: "text.bubble.fill") {
                        ChatsView()
                            .environment(connectionController)
                            .environment(runtime)
                            .navigationTitle(connectionName)
                    }

                    Tab("Messages", systemImage: "ellipsis.message.fill") {
                        MessagesView()
                            .environment(runtime)
                    }

                    Tab("Boards", systemImage: "newspaper.fill") {
                        if let runtime = connectionController.runtime(for: bookmark.id) {
                            BoardsView()
                                .environment(runtime)
                        }
                    }

                    Tab("Files", systemImage: "folder.fill") {
                        Text("Files")
                    }

                    Tab("Settings", systemImage: "gearshape.fill") {
                        Text("Settings")
                    }

                    Tab("Info", systemImage: "info.circle.fill") {
                        ServerInfoView()
                            .environment(connectionController)
                            .environment(runtime)
                            .navigationTitle(connectionName)
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
                                DisconnectAlert(askDisconnect: $askDisconnect, onConfirm: {
                                    connectionController.disconnect(connectionID: connectionID, runtime: runtime)
                                    dismiss()
                                })
                            )
                        }
                    }
                }
                .errorAlert(
                    error: $runtime.lastError,
                    source: "Connection",
                    serverName: connectionName,
                    connectionID: runtime.id
                )
            }
        }
#endif
    }

    private func connect() {
        if let bookmark {
            connectionController.connect(bookmark)
            return
        }

        if let configuration = connectionController.configuration(for: connectionID) {
            connectionController.connect(configuration)
        }
    }

    private func autoReconnectLabel(for runtime: ConnectionRuntime, now: Date) -> String {
        let fallback = max(0, Int(runtime.autoReconnectInterval.rounded()))
        let remaining = max(
            0,
            Int((runtime.autoReconnectNextAttemptAt?.timeIntervalSince(now) ?? TimeInterval(fallback)).rounded(.up))
        )

        if remaining > 0 {
            return "Auto-reconnect in \(remaining)s (attempt \(runtime.autoReconnectAttempt))"
        }

        return "Auto-reconnecting..."
    }

    private func bookmarkCurrentConnection() {
        print("bookmarkCurrentConnection")
        
        guard bookmark == nil else { return }
        guard let configuration = connectionController.configuration(for: connectionID) else { return }

        let newBookmark = Bookmark(
            id: configuration.id,
            name: configuration.name,
            hostname: configuration.hostname,
            login: configuration.login
        )
        newBookmark.cipherRawValue = configuration.cipher.rawValue
        newBookmark.compressionRawValue = configuration.compression.rawValue
        newBookmark.checksumRawValue = configuration.checksum.rawValue
        
        if let runtime = connectionController.runtime(for: configuration.id) {
            print("runtime \(runtime)")
            if let serverName = runtime.connection?.serverInfo?.serverName {
                print("serverName \(serverName)")
                newBookmark.name = serverName
            }
        }

        modelContext.insert(newBookmark)
        try? modelContext.save()

        if let password = configuration.password, !password.isEmpty {
            KeychainSwift().set(password, forKey: "\(configuration.login)@\(configuration.hostname)")
        }

        connectionController.markConnectionAsBookmarked(configuration.id)
    }
}


struct DisconnectAlert: ViewModifier {
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
