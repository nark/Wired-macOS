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
    
    @State  private var selectedBookmarkID: UUID? = nil
    @State var showBookmarkSheet: Bool = false
    @State var editedBookmark: Bookmark? = nil
    
    @AppStorage("transfersHeight") private var transfersHeight: Double = 0
    @State private var lastTransfersHeight: CGFloat = 200
    @State private var isTransfersVisible = false
    
    var body: some View {
        VSplitView {
            mainContent

            // Panneau transferts
            transfersPanel
                .frame(
                    minHeight: isTransfersVisible ? 200 : 0,
                    maxHeight: isTransfersVisible ? .infinity : 0
                )
                .animation(.smooth, value: isTransfersVisible)
        }
    }
    
    private var mainContent: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $selectedBookmarkID) {
                    Section {
                        ForEach(bookmarks, id: \.id) { bookmark in
                            ConnectionRowView(bookmark: bookmark)
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
                }
                
                Divider()
                
                HStack(spacing: 0) {
                    Button {
                        toggleTransfers()
                        
                    } label: {
                        Image(systemName: isTransfersVisible ? "menubar.arrow.down.rectangle" : "menubar.arrow.up.rectangle")
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
                        showBookmarkSheet.toggle()
                    } label: {
                        Label("New Connection", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showBookmarkSheet) {
                BookmarkFormView()
            }
            .sheet(item: $editedBookmark) { bookmark in
                BookmarkFormView(bookmark: bookmark)
            }
        } detail: {
            if let id = selectedBookmarkID,
               let bookmark = bookmarks.first(where: { $0.id == id }) {
                TabsView(bookmark: bookmark)
                    .environment(connectionController)
                    .environmentObject(transfers)
                    .id(bookmark.id)
            } else {
                Text("Select an item")
            }
        }
        .onAppear {
            print("on appear")
            for b in bookmarks {
                print("b \(b.name) \(b.connectAtStartup)")
                if b.connectAtStartup {
                    connectionController.connect(b)
                }
            }
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
                            .onChange(of: geo.size.height) { old, newHeight in
                                guard isTransfersVisible else { return }
                                guard newHeight > 30 else { return }

                                transfersHeight = newHeight
                                lastTransfersHeight = newHeight
                            }
                    }
                )
        }

    private func addItem() {
//        withAnimation {
//            let newItem = Bookmark(timestamp: Date())
//            modelContext.insert(newItem)
//        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(bookmarks[index])
            }
        }
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
