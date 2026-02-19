//
//  ContentView.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 18/12/2025.
//  Copyright © 2025 Read-Write. All rights reserved.
//

import SwiftUI
import SwiftData

struct MainView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var bookmarks: [Bookmark]
    @Environment(ConnectionController.self) private var connectionController
    @EnvironmentObject private var transfers: TransferManager

    @State private var selectedConnectionID: UUID? = nil
    @State private var editedBookmark: Bookmark? = nil

    @AppStorage("transfersHeight") private var transfersHeight: Double = 0
    @State private var lastTransfersHeight: CGFloat = 200
    @State private var isTransfersVisible = false

    private var activeTransfersCount: Int {
        transfers.transfers.filter { !$0.isStopped() }.count
    }

    private var selectedBookmark: Bookmark? {
        guard let id = selectedConnectionID else { return nil }
        return bookmarks.first(where: { $0.id == id })
    }

    private var selectedTemporaryConnection: TemporaryConnection? {
        guard let id = selectedConnectionID else { return nil }
        return connectionController.temporaryConnection(for: id)
    }

    var body: some View {
        @Bindable var connectionController = connectionController

        VSplitView {
            mainContent

            transfersPanel
                .frame(
                    minHeight: isTransfersVisible ? 200 : 0,
                    maxHeight: isTransfersVisible ? .infinity : 0
                )
                .animation(.smooth, value: isTransfersVisible)
        }
        .sheet(item: $connectionController.presentedNewConnection) { draft in
            NewConnectionFormView(draft: draft) { id in
                selectedConnectionID = id
            }
        }
    }

    private var mainContent: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $selectedConnectionID) {
                    Section {
                        ForEach(bookmarks, id: \.id) { bookmark in
                            ConnectionRowView(
                                connectionID: bookmark.id,
                                name: bookmark.name
                            )
                            .environment(connectionController)
                            .contextMenu {
                                Button("Edit") {
                                    editedBookmark = bookmark
                                }
                            }
                        }
                    } header: {
                        Text("Favorites")
                    }

                    if !connectionController.temporaryConnections.isEmpty {
                        Section {
                            ForEach(connectionController.temporaryConnections, id: \.id) { temporary in
                                ConnectionRowView(
                                    connectionID: temporary.id,
                                    name: temporary.name
                                )
                                .environment(connectionController)
                            }
                        } header: {
                            Text("Connections")
                        }
                    }
                }

                Divider()

                HStack(spacing: 0) {
                    Button {
                        toggleTransfers()

                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: isTransfersVisible ? "menubar.arrow.down.rectangle" : "menubar.arrow.up.rectangle")

                            if activeTransfersCount > 0 {
                                Text(activeTransfersCount > 99 ? "99" : "\(activeTransfersCount)")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 18, height: 18)
                                    .background(
                                        Circle()
                                            .fill(Color.red)
                                    )
                                    .offset(x: 10, y: -8)
                                    .transition(.scale(scale: 0.7).combined(with: .opacity))
                            }
                        }
                        .animation(.spring(response: 0.25, dampingFraction: 0.72), value: activeTransfersCount)
                    }
                    .foregroundStyle(isTransfersVisible ? .blue : .black)
                    .buttonStyle(.plain)
                    .help("Show Transfers")

                    Spacer()
                }
                .padding(8)
            }
#if os(macOS)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
#endif
            .toolbar {
#if os(iOS)
                ToolbarItem(placement: .navigation) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gear")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
#endif
                ToolbarItem {
                    Button {
                        connectionController.presentNewConnection()
                    } label: {
                        Label("New Connection", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $editedBookmark) { bookmark in
                BookmarkFormView(bookmark: bookmark)
            }
        } detail: {
            if let bookmark = selectedBookmark {
                TabsView(
                    connectionID: bookmark.id,
                    connectionName: bookmark.name,
                    bookmark: bookmark
                )
                .environment(connectionController)
                .environmentObject(transfers)
                .id(bookmark.id)
            } else if let temporary = selectedTemporaryConnection {
                TabsView(
                    connectionID: temporary.id,
                    connectionName: temporary.name,
                    bookmark: nil
                )
                .environment(connectionController)
                .environmentObject(transfers)
                .id(temporary.id)
            } else {
                Text("Select an item")
            }
        }
        .onAppear {
            for bookmark in bookmarks where bookmark.connectAtStartup {
                connectionController.connect(bookmark)
            }
        }
        .onChange(of: activeTransfersCount) { oldValue, newValue in
            guard newValue > oldValue else { return }
            guard !isTransfersVisible else { return }

            withAnimation(.smooth) {
                isTransfersVisible = true
                transfersHeight = max(lastTransfersHeight, 200)
            }
        }
        .onChange(of: connectionController.requestedSelectionID) { _, newValue in
            guard let newValue else { return }
            selectedConnectionID = newValue
            connectionController.requestedSelectionID = nil
        }
    }

    private var transfersPanel: some View {
        Color.gray.opacity(0.15)
            .overlay(
                TransfersView()
                    .environmentObject(transfers)
            )
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onChange(of: geo.size.height) { _, newHeight in
                            guard isTransfersVisible else { return }
                            guard newHeight > 30 else { return }

                            transfersHeight = newHeight
                            lastTransfersHeight = newHeight
                        }
                }
            )
    }

    private func toggleTransfers() {
        if isTransfersVisible {
            lastTransfersHeight = transfersHeight
            transfersHeight = 0
        } else {
            transfersHeight = lastTransfersHeight
        }
        isTransfersVisible.toggle()
    }
}
