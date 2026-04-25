//
//  ContentView.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 18/12/2025.
//  Copyright © 2025 Read-Write. All rights reserved.
//

import SwiftUI
import SwiftData
import KeychainSwift
import WiredSwift
#if os(macOS)
import AppKit
#endif

struct MainView: View {
    private enum SidebarSelection: Hashable {
        case connection(UUID)
        case trackerBookmark(UUID)
        case trackerCategory(UUID, String)
        case trackerServer(UUID, String)
        case trackerStatus(UUID, String)
    }

    private struct TrackerSidebarNode: Identifiable, Hashable {
        enum Kind: Hashable {
            case bookmark(TrackerBookmark)
            case category(bookmarkID: UUID, category: TrackerCategoryNode)
            case server(bookmarkID: UUID, server: TrackerServerNode)
            case status(bookmarkID: UUID, message: String)
        }

        let id: String
        let selection: SidebarSelection
        let kind: Kind
        let children: [TrackerSidebarNode]?
    }

    private struct TrackerServerInfoPresentation: Identifiable {
        let bookmarkID: UUID
        let server: TrackerServerNode

        var id: String { "\(bookmarkID)|\(server.id)" }
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query private var bookmarks: [Bookmark]
    @Query private var trackerBookmarks: [TrackerBookmark]
    @Environment(ConnectionController.self) private var connectionController
    @Environment(TrackerBrowserController.self) private var trackerBrowser
    @EnvironmentObject private var transfers: TransferManager

    @State private var windowConnectionID: UUID?
    @State private var listSelection: SidebarSelection?
    @State private var editedBookmark: Bookmark?
    @State private var editedTrackerBookmark: TrackerBookmark?
    @State private var showingNewTrackerSheet: Bool = false

    @State private var showDeleteBookmarkConfirmation: Bool = false
    @State private var bookmarkToDelete: Bookmark?
    @State private var showDeleteTrackerConfirmation: Bool = false
    @State private var trackerBookmarkToDelete: TrackerBookmark?
    @State private var inspectedTrackerServer: TrackerServerInfoPresentation?
    @AppStorage("transfersHeight") private var transfersHeight: Double = 0
    @AppStorage("CheckActiveConnectionsBeforeClosingWindowTab")
    private var checkActiveConnectionsBeforeClosingWindowTab: Bool = true
    @State private var lastTransfersHeight: CGFloat = 200
    @State private var isTransfersVisible = false
    @State private var isTabBarVisible = false
    @State private var windowNumber: Int?
#if os(iOS)
    @State private var iPadSplitVisibility: NavigationSplitViewVisibility = .doubleColumn
#elseif os(macOS)
    @State private var macSplitVisibility: NavigationSplitViewVisibility = .automatic
#endif

    private var splitColumnVisibility: Binding<NavigationSplitViewVisibility> {
#if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            return $iPadSplitVisibility
        }
        return .constant(.automatic)
#elseif os(macOS)
        return $macSplitVisibility
#endif
    }

    private var activeTransfersCount: Int {
        transfers.transfers.filter { !$0.isStopped() }.count
    }

    private var windowBookmark: Bookmark? {
        guard let id = windowConnectionID else { return nil }
        return bookmarks.first(where: { $0.id == id })
    }

    private var windowTemporaryConnection: TemporaryConnection? {
        guard let id = windowConnectionID else { return nil }
        return connectionController.temporaryConnection(for: id)
    }

    private var windowConnectionName: String? {
        windowBookmark?.name ?? windowTemporaryConnection?.name
    }

    private var windowRuntime: ConnectionRuntime? {
        guard let id = windowConnectionID else { return nil }
        return connectionController.runtime(for: id)
    }

    private var defaultAppTitle: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ??
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String) ??
        "Wired"
    }

    private var tabTitle: String {
        let baseTitle = windowConnectionName ?? defaultAppTitle

        guard let runtime = windowRuntime else { return baseTitle }
        let hasConnectionIssue =
            runtime.status == .disconnected &&
            (runtime.lastError != nil || runtime.isAutoReconnectScheduled)

        return hasConnectionIssue ? "⚠︎ \(baseTitle)" : baseTitle
    }

    private var newConnectionSheetBinding: Binding<NewConnectionDraft?> {
        Binding(
            get: {
                guard !connectionController.suppressPresentedNewConnectionSheet else { return nil }
                guard let draft = connectionController.presentedNewConnection else { return nil }
#if os(macOS)
                if let presenterWindowNumber = connectionController.presentedNewConnectionWindowNumber {
                    guard presenterWindowNumber == windowNumber else { return nil }
                }
#endif
                return draft
            },
            set: { newValue in
                connectionController.presentedNewConnection = newValue
                if newValue == nil {
#if os(macOS)
                    connectionController.presentedNewConnectionWindowNumber = nil
#endif
                }
            }
        )
    }

    private var changePasswordSheetBinding: Binding<Bool> {
        Binding(
            get: {
                guard connectionController.presentChangePassword != nil else { return false }
                #if os(macOS)
                if let presenterWindowNumber = connectionController.presentChangePasswordWindowNumber {
                    guard presenterWindowNumber == windowNumber else { return false }
                }
                #endif
                return true
            },
            set: { if !$0 {
                connectionController.presentChangePassword = nil
                connectionController.presentChangePasswordWindowNumber = nil
                connectionController.presentChangePasswordIsMandatory = false
            }}
        )
    }

    private var listSelectionBinding: Binding<UUID?> {
        Binding(
            get: {
                guard case let .connection(id) = listSelection else { return nil }
                return id
            },
            set: { newValue in
                listSelection = newValue.map(SidebarSelection.connection)
            }
        )
    }

    private var sidebarSelectionBinding: Binding<SidebarSelection?> {
        Binding(
            get: { listSelection },
            set: { newValue in
                listSelection = newValue
                guard let newValue else { return }
                guard case let .connection(connectionID) = newValue else { return }

#if os(macOS)
                // If the connection lives in its own tab, focus that tab and
                // restore the sidebar selection to this window's connection.
                if connectionController.hasWindowAssociation(for: connectionID),
                   connectionController.focusWindow(for: connectionID) {
                    let currentIsLive: Bool = {
                        guard let id = windowConnectionID,
                              let r = connectionController.runtime(for: id) else { return false }
                        return r.status == .connected || r.status == .connecting
                    }()
                    if currentIsLive {
                        listSelection = windowConnectionID.map(SidebarSelection.connection)
                        return
                    }
                    // This window has no live connection — fall through and adopt the clicked one.
                }

                // No window association, focusWindow failed, or this window's connection
                // is gone (e.g. after a sibling tab closed). If the clicked connection is
                // live, show it here with a single click.
                if let r = connectionController.runtime(for: connectionID),
                   r.status == .connected || r.status == .connecting {
                    windowConnectionID = connectionID
                    connectionController.activeConnectionID = connectionID
                }
#endif
            }
        )
    }

    var body: some View {
        @Bindable var connectionController = connectionController

        rootContent
            #if os(macOS)
            .navigationTitle(tabTitle)
            .background(
                MainWindowCloseConfirmationView(
                    selectedConnectionID: windowConnectionID,
                    checkBeforeClosing: checkActiveConnectionsBeforeClosingWindowTab,
                    connectionController: connectionController,
                    onWindowBecameKey: {
                        if windowConnectionID != nil {
                            listSelection = windowConnectionID.map(SidebarSelection.connection)
                            connectionController.activeConnectionID = windowConnectionID
                        } else {
                            // State was reset (e.g. after a sibling tab closed and SwiftUI
                            // re-evaluated this scene). Restore the connection context so the
                            // view doesn't remain stuck on the connections list.
                            restoreWindowConnectionIfNeeded()
                        }
                    },
                    onWindowChanged: { window in
                        windowNumber = window.windowNumber
                    },
                    onTabBarVisibilityChanged: { isVisible in
                        isTabBarVisible = isVisible
                    },
                    onRequestDismiss: { dismiss() }
                )
                .frame(width: 0, height: 0)
            )
            #endif
            .sheet(isPresented: changePasswordSheetBinding) {
                if let connectionID = connectionController.presentChangePassword {
                    ChangePasswordView(
                        connectionID: connectionID,
                        isMandatory: connectionController.presentChangePasswordIsMandatory
                    )
                    .environment(connectionController)
                }
            }
            .sheet(item: newConnectionSheetBinding) { draft in
                NewConnectionFormView(draft: draft) { id in
                    connectionController.suppressPresentedNewConnectionSheet = true
                    if windowConnectionID == nil {
                        // Reuse the current (empty) window — avoids a duplicate tab
                        // that would also pick up the same connection via restoreWindowConnectionIfNeeded.
                        windowConnectionID = id
                        listSelection = .connection(id)
                        connectionController.activeConnectionID = id
                    } else {
                        connectionController.requestedSelectionID = id
                        openMainTab()
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        connectionController.suppressPresentedNewConnectionSheet = false
                    }
                }
            }
            .onAppear {
                performInitialLaunchFlowIfNeeded()
                consumePendingSelectionIfNeeded()
                restoreWindowConnectionIfNeeded()
                listSelection = windowConnectionID.map(SidebarSelection.connection)
                connectionController.activeConnectionID = windowConnectionID
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
                _ = newValue
                consumePendingSelectionIfNeeded()
                restoreWindowConnectionIfNeeded()
            }
            .onChange(of: windowConnectionID) { _, newValue in
                connectionController.activeConnectionID = newValue
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
    }

    @ViewBuilder
    private var rootContent: some View {
        #if os(macOS)
        VSplitView {
            mainContent

            transfersPanel
                .frame(
                    minHeight: isTransfersVisible ? 200 : 0,
                    maxHeight: isTransfersVisible ? .infinity : 0
                )
                .animation(.smooth, value: isTransfersVisible)
        }
        #else
        VStack(spacing: 0) {
            mainContent

            if isTransfersVisible {
                transfersPanel
                    .frame(height: max(lastTransfersHeight, 200))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
        .animation(.smooth, value: isTransfersVisible)
        #endif
    }

    @ViewBuilder
    private var mainContent: some View {
        #if os(iOS)
        if horizontalSizeClass == .compact {
            compactMainContent
        } else {
            splitMainContent
        }
        #else
        splitMainContent
        #endif
    }

    private var splitMainContent: some View {
        NavigationSplitView(
            columnVisibility: splitColumnVisibility
        ) {
            sidebarContent
                #if os(macOS)
                    .padding(.top, isTabBarVisible ? 30 : 0)
                    .navigationSplitViewColumnWidth(min: 180, ideal: 200)
                #endif
        } detail: {
            detailPane(for: windowConnectionID)
                .wiredContainerBackground()
        }
        .wiredToolbarBackgroundVisible()
        .wiredWindowToolbar(mode: splitViewToolbarMode) {
            mainToolbar
        }
        .sheet(item: $editedBookmark) { bookmark in
            BookmarkFormView(bookmark: bookmark)
                .id(bookmark.id)
        }
        .sheet(item: $editedTrackerBookmark) { trackerBookmark in
            TrackerBookmarkFormView(trackerBookmark: trackerBookmark)
                .id(trackerBookmark.id)
        }
        .sheet(isPresented: $showingNewTrackerSheet) {
            TrackerBookmarkFormView()
                .id("new-tracker-bookmark")
        }
        .alert("Delete Bookmark", isPresented: $showDeleteBookmarkConfirmation) {
            Button("Cancel", role: .cancel) {
            }

            Button("Delete", role: .destructive) {
                deleteBookmark()
            }
        }
        .alert("Delete Tracker", isPresented: $showDeleteTrackerConfirmation) {
            Button("Cancel", role: .cancel) {
            }

            Button("Delete", role: .destructive) {
                deleteTrackerBookmark()
            }
        }
    }

    #if os(iOS)
    private var compactMainContent: some View {
        NavigationStack {
            if let selectedID = windowConnectionID,
               bookmark(for: selectedID) != nil || temporaryConnection(for: selectedID) != nil {
                detailPane(for: selectedID)
                    .navigationTitle(connectionName(for: selectedID))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        compactDetailToolbar
                    }
            } else {
                compactSidebarList
                    .navigationTitle(defaultAppTitle)
                    .toolbar {
                        mainToolbar
                    }
            }
        }
        .sheet(item: $editedBookmark) { bookmark in
            BookmarkFormView(bookmark: bookmark)
                .id(bookmark.id)
        }
        .sheet(item: $editedTrackerBookmark) { trackerBookmark in
            TrackerBookmarkFormView(trackerBookmark: trackerBookmark)
                .id(trackerBookmark.id)
        }
        .sheet(isPresented: $showingNewTrackerSheet) {
            TrackerBookmarkFormView()
                .id("new-tracker-bookmark")
        }
        .alert("Delete Bookmark", isPresented: $showDeleteBookmarkConfirmation) {
            Button("Cancel", role: .cancel) {
            }

            Button("Delete", role: .destructive) {
                deleteBookmark()
            }
        }
        .alert("Delete Tracker", isPresented: $showDeleteTrackerConfirmation) {
            Button("Cancel", role: .cancel) {
            }

            Button("Delete", role: .destructive) {
                deleteTrackerBookmark()
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
    }
    #endif

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            connectionList

            Divider()

            transfersToggleBar
        }
        .wiredWindowToolbar(mode: sidebarToolbarMode) {
            mainToolbar
        }
    }

    @ViewBuilder
    private var connectionList: some View {
        #if os(macOS)
        List(selection: sidebarSelectionBinding) {
            connectionSections
        }
        .contextMenu(forSelectionType: SidebarSelection.self) { _ in
            EmptyView()
        } primaryAction: { selection in
            handleSidebarPrimaryAction(selection)
        }
        #else
        List(selection: listSelectionBinding) {
            connectionSections
        }
        #endif
    }

    private var compactSidebarList: some View {
        List {
            Section {
                ForEach(bookmarks, id: \.id) { bookmark in
                    Button {
                        handleConnectionPrimaryAction([bookmark.id])
                    } label: {
                        connectionRow(connectionID: bookmark.id, name: bookmark.name)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Favorites")
            }

            trackerSection

            if !connectionController.temporaryConnections.isEmpty {
                Section {
                    ForEach(connectionController.temporaryConnections, id: \.id) { temporary in
                        Button {
                            handleConnectionPrimaryAction([temporary.id])
                        } label: {
                            connectionRow(connectionID: temporary.id, name: temporary.name)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Connections")
                }
            }
        }
    }

    @ViewBuilder
    private var connectionSections: some View {
        Section {
            ForEach(bookmarks, id: \.id) { bookmark in
                connectionRow(connectionID: bookmark.id, name: bookmark.name)
                    .tag(SidebarSelection.connection(bookmark.id))
            }
        } header: {
            Text("Favorites")
        }

        if !connectionController.temporaryConnections.isEmpty {
            Section {
                ForEach(connectionController.temporaryConnections, id: \.id) { temporary in
                    connectionRow(connectionID: temporary.id, name: temporary.name)
                        .tag(SidebarSelection.connection(temporary.id))
                }
            } header: {
                Text("Connections")
            }
        }

        trackerSection
    }

    private var sortedTrackerBookmarks: [TrackerBookmark] {
        trackerBookmarks.sorted {
            if $0.sortOrder != $1.sortOrder {
                return $0.sortOrder < $1.sortOrder
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private var trackerSection: some View {
        Section {
            if sortedTrackerBookmarks.isEmpty {
                Button {
                    showingNewTrackerSheet = true
                } label: {
                    Label("Add Tracker", systemImage: "plus.circle")
                }
                .buttonStyle(.plain)
            } else {
                OutlineGroup(trackerSidebarRoots, children: \.children) { node in
                    trackerSidebarNodeRow(node)
                        .tag(node.selection)
                }
            }
        } header: {
            HStack {
                Text("Trackers")
                Spacer()
                Button {
                    showingNewTrackerSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var transfersToggleBar: some View {
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
            .foregroundStyle(isTransfersVisible ? .blue : .primary)
            .buttonStyle(.plain)
            .help("Show Transfers")

            Spacer()
        }
        .padding(9)
    }

    private func connectionRow(connectionID: UUID, name: String) -> some View {
        ConnectionRowView(connectionID: connectionID, name: name)
            .environment(connectionController)
            .contextMenu {
                connectionContextMenu(for: Set([connectionID]))
            }
#if os(iOS)
            .contentShape(Rectangle())
#endif
    }

    @ViewBuilder
    private func trackerSidebarNodeRow(_ node: TrackerSidebarNode) -> some View {
        switch node.kind {
        case .bookmark(let trackerBookmark):
            trackerBookmarkLabel(trackerBookmark)
                .contextMenu {
                    Button("Reload") {
                        trackerBrowser.refresh(trackerBookmark)
                    }

                    Divider()

                    Button("Edit") {
                        editedTrackerBookmark = trackerBookmark
                    }

                    Button("Delete") {
                        trackerBookmarkToDelete = trackerBookmark
                        showDeleteTrackerConfirmation = true
                    }
                }
                .task(id: trackerBookmark.id) {
                    trackerBrowser.refreshIfNeeded(trackerBookmark)
                }

        case .category(_, let category):
            Label(category.name, systemImage: "folder")

        case .server(_, let server):
            trackerServerLabel(server)
                .contentShape(Rectangle())
                .contextMenu {
                    Button("Connect") {
                        connectToTrackerServer(server)
                    }

                    Button("Get Info") {
                        inspectedTrackerServer = TrackerServerInfoPresentation(
                            bookmarkID: bookmarkID(for: node),
                            server: server
                        )
                    }

                    Divider()

                    Button("Add to Favorites") {
                        addTrackerServerToFavorites(server)
                    }

                    if server.isTracker {
                        Button("Add to Trackers") {
                            addTrackerBookmark(from: server)
                        }
                    }
                }
                .popover(
                    isPresented: Binding(
                        get: {
                            inspectedTrackerServer?.id == TrackerServerInfoPresentation(
                                bookmarkID: bookmarkID(for: node),
                                server: server
                            ).id
                        },
                        set: { isPresented in
                            if !isPresented,
                               inspectedTrackerServer?.id == TrackerServerInfoPresentation(
                                bookmarkID: bookmarkID(for: node),
                                server: server
                               ).id {
                                inspectedTrackerServer = nil
                            }
                        }
                    ),
                    attachmentAnchor: .rect(.bounds),
                    arrowEdge: .trailing
                ) {
                    TrackerServerInfoView(server: server)
                        .frame(minWidth: 360, idealWidth: 420)
                }

        case .status(_, let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func handleSidebarPrimaryAction(_ selection: Set<SidebarSelection>) {
        guard let first = selection.first else { return }

        switch first {
        case .connection(let id):
            handleConnectionPrimaryAction([id])
        case .trackerServer(let bookmarkID, let serverID):
            guard let server = trackerServer(for: bookmarkID, serverID: serverID) else { return }
            connectToTrackerServer(server)
        case .trackerBookmark, .trackerCategory, .trackerStatus:
            break
        }
    }

    private func bookmarkID(for node: TrackerSidebarNode) -> UUID {
        switch node.kind {
        case .bookmark(let trackerBookmark):
            return trackerBookmark.id
        case .category(let bookmarkID, _):
            return bookmarkID
        case .server(let bookmarkID, _):
            return bookmarkID
        case .status(let bookmarkID, _):
            return bookmarkID
        }
    }

    private func trackerBookmarkLabel(_ trackerBookmark: TrackerBookmark) -> some View {
        let state = trackerBrowser.state(for: trackerBookmark.id)

        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(.secondary)
                Text(trackerBookmark.name)
                if state.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text(trackerBookmark.displayAddress)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 24)
        }
    }

    private func trackerServerLabel(_ server: TrackerServerNode) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: server.isTracker ? "point.3.connected.trianglepath.dotted" : "server.rack")
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(server.name)
                    .foregroundStyle(.primary)

                if !server.serverDescription.isEmpty {
                    Text(server.serverDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    Text("\(server.users) users")
                    Text("\(server.filesCount) files")
                    Text(byteCountFormatter.string(fromByteCount: Int64(server.filesSize)))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    private func detailPane(for connectionID: UUID?) -> some View {
        ZStack {
            if let bookmark = bookmark(for: connectionID) {
                TabsView(
                    connectionID: bookmark.id,
                    connectionName: bookmark.name,
                    bookmark: bookmark
                )
                .environment(connectionController)
                .environmentObject(transfers)
                .id(bookmark.id)
            } else if let temporary = temporaryConnection(for: connectionID) {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    #if os(iOS)
    @ToolbarContentBuilder
    private var compactDetailToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                windowConnectionID = nil
                listSelection = nil
                connectionController.activeConnectionID = nil
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Connections")
        }
        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink {
                SettingsView()
            } label: {
                Image(systemName: "gear")
            }
        }
    }
    #endif

    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        #if os(iOS)
        ToolbarItem(placement: .navigationBarLeading) {
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
        #if os(macOS)
        ToolbarItem(placement: .primaryAction) {
            Button {
                connectionController.presentedNewConnectionWindowNumber = windowNumber
                connectionController.presentNewConnection()
            } label: {
                Label("New Connection", systemImage: "plus")
            }
        }
        #else
        ToolbarItem {
            Button {
                connectionController.presentNewConnection()
            } label: {
                Label("New Connection", systemImage: "plus")
            }
        }
        #endif
    }

    private var splitViewToolbarMode: WiredWindowToolbarMode {
        #if os(macOS)
        if #available(macOS 15.0, *) {
            return .full
        }

        // On Sonoma, attaching custom toolbar items directly to the root split view
        // crashes in AppKit while the window toolbar is being assembled.
        return .systemOnly
        #else
        return .full
        #endif
    }

    private var sidebarToolbarMode: WiredWindowToolbarMode {
        #if os(macOS)
        if #available(macOS 15.0, *) {
            return .disabled
        }

        // Reattach the custom toolbar item from the sidebar content instead.
        return .full
        #else
        return .disabled
        #endif
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

    private func deleteBookmark() {
        if let bookmarkToDelete {
            // disconnect if needed
            if let runtime = connectionController.runtime(for: bookmarkToDelete.id) {
                connectionController.disconnect(connectionID: bookmarkToDelete.id, runtime: runtime)
            }

            modelContext.delete(bookmarkToDelete)
            self.bookmarkToDelete = nil
        }

        showDeleteBookmarkConfirmation = false
    }

    private func deleteTrackerBookmark() {
        if let trackerBookmarkToDelete {
            KeychainSwift().delete(trackerBookmarkToDelete.credentialKey)
            modelContext.delete(trackerBookmarkToDelete)
            trackerBrowser.clear(for: trackerBookmarkToDelete.id)
            self.trackerBookmarkToDelete = nil
            try? modelContext.save()
        }

        showDeleteTrackerConfirmation = false
    }

    private func disconnect(_ id: UUID) {
        if let runtime = connectionController.runtime(for: id) {
            connectionController.disconnect(connectionID: id, runtime: runtime)
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

    private func consumePendingSelectionIfNeeded() {
        guard windowConnectionID == nil,
              let requested = connectionController.requestedSelectionID else {
            return
        }
        windowConnectionID = requested
        listSelection = .connection(requested)
        connectionController.requestedSelectionID = nil
        connectionController.activeConnectionID = requested
    }

    private func restoreWindowConnectionIfNeeded() {
        guard windowConnectionID == nil else { return }

        if case let .connection(connectionID) = listSelection,
           hasConnectionContext(connectionID) {
            windowConnectionID = connectionID
            connectionController.activeConnectionID = connectionID
            return
        }

        // Prefer an actually-connected session. firstActiveConnectionID() may return
        // the stale activeConnectionID whose task is still winding down but whose
        // status is already .disconnected — which would show the wrong (dead) connection.
        let id = connectionController.activeConnectedConnectionIDs().first
            ?? connectionController.firstActiveConnectionID()
        guard let id else { return }
        windowConnectionID = id
        listSelection = .connection(id)
        connectionController.activeConnectionID = id
    }

    private func performInitialLaunchFlowIfNeeded() {
        guard !connectionController.didPerformInitialLaunchFlow else { return }
        connectionController.didPerformInitialLaunchFlow = true

        let startupBookmarks = bookmarks.filter { $0.connectAtStartup }
        guard !startupBookmarks.isEmpty else {
            if bookmarks.isEmpty {
                connectionController.presentNewConnection()
            }
            return
        }

        if let first = startupBookmarks.first {
            windowConnectionID = first.id
            listSelection = .connection(first.id)
            connectionController.activeConnectionID = first.id
            connectionController.connect(first)
        }

        for (index, bookmark) in startupBookmarks.dropFirst().enumerated() {
            let delay = 0.10 * Double(index + 1)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                connectInNewTab(bookmark)
            }
        }
    }

    private func openOrSelectBookmark(_ bookmark: Bookmark) {
        // WiredClient-like behavior: opening a bookmark creates a dedicated tab/window.
        if hasConnectionContext(bookmark.id) {
#if os(macOS)
            if connectionController.focusWindow(for: bookmark.id) {
                return
            }
            // Window registry lost this connection — show it in the current window instead.
            selectConnection(bookmark.id)
            return
#else
            windowConnectionID = bookmark.id
            listSelection = .connection(bookmark.id)
            connectionController.activeConnectionID = bookmark.id
            return
#endif
        }

        // Reuse the empty main window for the first connection.
        if windowConnectionID == nil {
            windowConnectionID = bookmark.id
            listSelection = .connection(bookmark.id)
            connectionController.activeConnectionID = bookmark.id
            connectionController.connect(bookmark)
            return
        }

        connectInNewTab(bookmark)
    }

    private func bookmark(for id: UUID) -> Bookmark? {
        bookmarks.first(where: { $0.id == id })
    }

    private func bookmark(for id: UUID?) -> Bookmark? {
        guard let id else { return nil }
        return bookmark(for: id)
    }

    private func temporaryConnection(for id: UUID?) -> TemporaryConnection? {
        guard let id else { return nil }
        return connectionController.temporaryConnection(for: id)
    }

    private func selectConnection(_ id: UUID) {
        windowConnectionID = id
        listSelection = .connection(id)
        connectionController.activeConnectionID = id
    }

    private func connectionName(for id: UUID) -> String {
        if let bookmark = bookmark(for: id) {
            return bookmark.name
        }
        if let temporary = temporaryConnection(for: id) {
            return temporary.name
        }
        return "Connection"
    }

    private func bookmarkConnection(_ id: UUID) {
        guard bookmark(for: id) == nil else { return }
        guard let configuration = connectionController.configuration(for: id) else { return }

        let newBookmark = Bookmark(
            id: configuration.id,
            name: configuration.name,
            hostname: configuration.hostname,
            login: configuration.login
        )
        newBookmark.cipherRawValue = configuration.cipher.rawValue
        newBookmark.compressionRawValue = configuration.compression.rawValue
        newBookmark.checksumRawValue = configuration.checksum.rawValue

        if let runtime = connectionController.runtime(for: id),
           let serverName = runtime.serverInfo?.serverName,
           !serverName.isEmpty {
            newBookmark.name = serverName
        }

        modelContext.insert(newBookmark)
        try? modelContext.save()

        if let password = configuration.password, !password.isEmpty {
            KeychainSwift().set(password, forKey: "\(configuration.login)@\(configuration.hostname)")
        }

        connectionController.markConnectionAsBookmarked(id)
    }

    private func draft(for server: TrackerServerNode) -> NewConnectionDraft? {
        guard !server.urlString.isEmpty else { return nil }

        let url = Url(withString: server.urlString)
        guard !url.hostname.isEmpty else { return nil }

        let hostname = url.port == Wired.wiredPort ? url.hostname : "\(url.hostname):\(url.port)"
        return NewConnectionDraft(
            hostname: hostname,
            login: url.login,
            password: url.password
        )
    }

    private func connectToTrackerServer(_ server: TrackerServerNode) {
        guard let draft = draft(for: server),
              let connectionID = connectionController.connectOrReuseTemporary(draft) else {
            return
        }

#if os(macOS)
        if windowConnectionID == nil {
            windowConnectionID = connectionID
            listSelection = .connection(connectionID)
            connectionController.activeConnectionID = connectionID
        } else {
            connectionController.requestedSelectionID = connectionID
            openMainTab()
        }
#else
        selectConnection(connectionID)
#endif
    }

    private func addTrackerServerToFavorites(_ server: TrackerServerNode) {
        guard let draft = draft(for: server) else { return }

        let bookmark = Bookmark(
            name: server.name,
            hostname: draft.hostname,
            login: draft.login
        )
        modelContext.insert(bookmark)

        if !draft.password.isEmpty {
            KeychainSwift().set(draft.password, forKey: "\(draft.login)@\(draft.hostname)")
        }

        try? modelContext.save()
    }

    private func addTrackerBookmark(from server: TrackerServerNode) {
        let url = Url(withString: server.urlString)
        guard !url.hostname.isEmpty else { return }

        let bookmark = TrackerBookmark(
            name: server.name,
            hostname: url.hostname,
            port: url.port,
            login: url.login
        )
        modelContext.insert(bookmark)

        if !url.password.isEmpty {
            KeychainSwift().set(url.password, forKey: bookmark.credentialKey)
        }

        try? modelContext.save()
    }

    private func trackerServer(for bookmarkID: UUID, serverID: String) -> TrackerServerNode? {
        let state = trackerBrowser.state(for: bookmarkID)
        if let rootMatch = state.rootServers.first(where: { $0.id == serverID }) {
            return rootMatch
        }

        func search(categories: [TrackerCategoryNode]) -> TrackerServerNode? {
            for category in categories {
                if let match = category.servers.first(where: { $0.id == serverID }) {
                    return match
                }
                if let nested = search(categories: category.categories) {
                    return nested
                }
            }
            return nil
        }

        return search(categories: state.categories)
    }

    private var trackerSidebarRoots: [TrackerSidebarNode] {
        sortedTrackerBookmarks.map(makeTrackerBookmarkNode)
    }

    private func makeTrackerBookmarkNode(_ trackerBookmark: TrackerBookmark) -> TrackerSidebarNode {
        let state = trackerBrowser.state(for: trackerBookmark.id)
        let bookmarkID = trackerBookmark.id

        var children: [TrackerSidebarNode] = []
        children.append(contentsOf: state.categories.map { makeTrackerCategoryNode(bookmarkID: bookmarkID, category: $0) })
        children.append(contentsOf: state.rootServers.map { makeTrackerServerNode(bookmarkID: bookmarkID, server: $0) })

        if state.isLoading && children.isEmpty {
            children.append(
                TrackerSidebarNode(
                    id: "tracker-status-\(bookmarkID)-loading",
                    selection: .trackerStatus(bookmarkID, "loading"),
                    kind: .status(bookmarkID: bookmarkID, message: "Loading tracker…"),
                    children: nil
                )
            )
        } else if let lastError = state.lastError, children.isEmpty {
            children.append(
                TrackerSidebarNode(
                    id: "tracker-status-\(bookmarkID)-error",
                    selection: .trackerStatus(bookmarkID, "error"),
                    kind: .status(bookmarkID: bookmarkID, message: lastError),
                    children: nil
                )
            )
        } else if !state.isLoading && children.isEmpty {
            children.append(
                TrackerSidebarNode(
                    id: "tracker-status-\(bookmarkID)-empty",
                    selection: .trackerStatus(bookmarkID, "empty"),
                    kind: .status(bookmarkID: bookmarkID, message: "No servers listed"),
                    children: nil
                )
            )
        }

        return TrackerSidebarNode(
            id: "tracker-bookmark-\(bookmarkID)",
            selection: .trackerBookmark(bookmarkID),
            kind: .bookmark(trackerBookmark),
            children: children
        )
    }

    private func makeTrackerCategoryNode(bookmarkID: UUID, category: TrackerCategoryNode) -> TrackerSidebarNode {
        let nestedChildren = category.categories.map {
            makeTrackerCategoryNode(bookmarkID: bookmarkID, category: $0)
        } + category.servers.map {
            makeTrackerServerNode(bookmarkID: bookmarkID, server: $0)
        }

        return TrackerSidebarNode(
            id: "tracker-category-\(bookmarkID)-\(category.path)",
            selection: .trackerCategory(bookmarkID, category.path),
            kind: .category(bookmarkID: bookmarkID, category: category),
            children: nestedChildren
        )
    }

    private func makeTrackerServerNode(bookmarkID: UUID, server: TrackerServerNode) -> TrackerSidebarNode {
        TrackerSidebarNode(
            id: "tracker-server-\(bookmarkID)-\(server.id)",
            selection: .trackerServer(bookmarkID, server.id),
            kind: .server(bookmarkID: bookmarkID, server: server),
            children: nil
        )
    }

    @ViewBuilder
    private func connectionContextMenu(for selection: Set<UUID>) -> some View {
        if let id = selection.first {
            if let bookmark = bookmark(for: id) {
                if isConnectionActive(id) {
                    Button("Disconnect") {
                        disconnect(id)
                    }
                } else {
                    Button("Connect") {
                        connectFromContextMenu(id)
                    }
                }

                Divider()

                Button("Edit") {
                    editedBookmark = bookmark
                }

                Divider()

                Button("Delete") {
                    showDeleteBookmarkConfirmation = true
                    bookmarkToDelete = bookmark
                }
            } else {
                let hasConfiguration = connectionController.configuration(for: id) != nil

                if isConnectionActive(id) {
                    Button("Disconnect") {
                        disconnect(id)
                    }
                } else if hasConfiguration {
                    Button("Connect") {
                        connectFromContextMenu(id)
                    }
                }

                if hasConfiguration {
                    Divider()
                    Button("Add to Favorites") {
                        bookmarkConnection(id)
                    }
                }
            }
        }
    }

    private func connectFromContextMenu(_ id: UUID) {
        if let bookmark = bookmark(for: id) {
#if os(macOS)
            if connectionController.hasWindowAssociation(for: id),
               connectionController.focusWindow(for: id) {
                connectionController.connect(bookmark)
                return
            }
#endif
            windowConnectionID = id
            listSelection = .connection(id)
            connectionController.activeConnectionID = id
            connectionController.connect(bookmark)
            return
        }

        guard let configuration = connectionController.configuration(for: id) else { return }

#if os(macOS)
        if connectionController.hasWindowAssociation(for: id),
           connectionController.focusWindow(for: id) {
            connectionController.connect(configuration)
            return
        }
#endif

        windowConnectionID = id
        listSelection = .connection(id)
        connectionController.activeConnectionID = id
        connectionController.connect(configuration)
    }

    private func handleConnectionPrimaryAction(_ selection: Set<UUID>) {
        guard let id = selection.first else { return }
        if let bookmark = bookmark(for: id) {
            if isConnectionActive(id) {
                // Already connected: focus the existing window/tab.
                openOrSelectBookmark(bookmark)
            } else {
                // Not connected (first open or after disconnect): connect.
                connectFromContextMenu(id)
            }
            return
        }

        guard hasConnectionContext(id) else { return }

#if os(macOS)
        if connectionController.hasWindowAssociation(for: id),
           connectionController.focusWindow(for: id) {
            return
        }
#endif

        if let configuration = connectionController.configuration(for: id) {
            connectionController.requestedSelectionID = id
            openMainTab()
            connectionController.connect(configuration)
            return
        }

        windowConnectionID = id
        listSelection = .connection(id)
        connectionController.activeConnectionID = id
    }

    private func isConnectionActive(_ id: UUID) -> Bool {
        guard let runtime = connectionController.runtime(for: id) else { return false }
        return runtime.status != .disconnected
    }

    private func hasConnectionContext(_ id: UUID) -> Bool {
        connectionController.runtime(for: id) != nil
    }

    private func openMainWindow() {
#if os(macOS)
        openWindow(id: "main")
#endif
    }

    private func openMainTab() {
#if os(macOS)
        let sourceWindow = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible }) ?? NSApp.windows.first
        let existingWindows = Set(NSApp.windows.map { ObjectIdentifier($0) })
        openMainWindow()
        attachNewMainWindowAsTab(existingWindows: existingWindows, preferredSourceWindow: sourceWindow)
#else
        if let requested = connectionController.requestedSelectionID {
            windowConnectionID = requested
            listSelection = .connection(requested)
            connectionController.activeConnectionID = requested
        }
#endif
    }

#if os(macOS)
    private func attachNewMainWindowAsTab(
        existingWindows: Set<ObjectIdentifier>,
        preferredSourceWindow: NSWindow?,
        attempt: Int = 0
    ) {
        if attempt > 10 { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            guard let newWindow = NSApp.windows.first(where: { !existingWindows.contains(ObjectIdentifier($0)) }) else {
                attachNewMainWindowAsTab(existingWindows: existingWindows, preferredSourceWindow: preferredSourceWindow, attempt: attempt + 1)
                return
            }

            let sourceWindow = preferredSourceWindow
                ?? NSApp.windows.first(where: { existingWindows.contains(ObjectIdentifier($0)) })
                ?? NSApp.keyWindow
                ?? NSApp.mainWindow
            guard let sourceWindow, newWindow !== sourceWindow else {
                attachNewMainWindowAsTab(existingWindows: existingWindows, preferredSourceWindow: preferredSourceWindow, attempt: attempt + 1)
                return
            }

            sourceWindow.tabbingMode = .preferred
            sourceWindow.tabbingIdentifier = "WiredMain"
            newWindow.tabbingMode = .preferred
            newWindow.tabbingIdentifier = "WiredMain"
            newWindow.orderOut(nil)
            sourceWindow.addTabbedWindow(newWindow, ordered: .above)
            sourceWindow.tabGroup?.selectedWindow = newWindow
            newWindow.makeKeyAndOrderFront(nil)
        }
    }
#endif

    private func connectInNewWindow(_ bookmark: Bookmark) {
        connectionController.requestedSelectionID = bookmark.id
#if os(macOS)
        openMainWindow()
#else
        windowConnectionID = bookmark.id
        listSelection = .connection(bookmark.id)
        connectionController.activeConnectionID = bookmark.id
#endif
        connectionController.connect(bookmark)
    }

    private func connectInNewTab(_ bookmark: Bookmark) {
        connectionController.requestedSelectionID = bookmark.id
#if os(macOS)
        openMainTab()
#else
        windowConnectionID = bookmark.id
        listSelection = .connection(bookmark.id)
        connectionController.activeConnectionID = bookmark.id
#endif
        connectionController.connect(bookmark)
    }
}

#if os(macOS)
private struct MainWindowCloseConfirmationView: NSViewRepresentable {
    let selectedConnectionID: UUID?
    let checkBeforeClosing: Bool
    let connectionController: ConnectionController
    let onWindowBecameKey: () -> Void
    let onWindowChanged: (NSWindow) -> Void
    let onTabBarVisibilityChanged: (Bool) -> Void
    let onRequestDismiss: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.selectedConnectionID = selectedConnectionID
        context.coordinator.checkBeforeClosing = checkBeforeClosing
        context.coordinator.connectionController = connectionController
        context.coordinator.onWindowBecameKey = onWindowBecameKey
        context.coordinator.onWindowChanged = onWindowChanged
        context.coordinator.onTabBarVisibilityChanged = onTabBarVisibilityChanged
        context.coordinator.onRequestDismiss = onRequestDismiss
        context.coordinator.attach(to: nsView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            selectedConnectionID: selectedConnectionID,
            checkBeforeClosing: checkBeforeClosing,
            connectionController: connectionController,
            onWindowBecameKey: onWindowBecameKey,
            onWindowChanged: onWindowChanged,
            onTabBarVisibilityChanged: onTabBarVisibilityChanged,
            onRequestDismiss: onRequestDismiss
        )
    }

    @MainActor
    final class Coordinator: NSObject {
        fileprivate var selectedConnectionID: UUID?
        fileprivate var checkBeforeClosing: Bool
        fileprivate weak var connectionController: ConnectionController?
        fileprivate var onWindowBecameKey: () -> Void
        fileprivate var onWindowChanged: (NSWindow) -> Void
        fileprivate var onTabBarVisibilityChanged: (Bool) -> Void
        fileprivate var onRequestDismiss: () -> Void

        private var observedWindow: NSWindow?
        private var closeDelegate: WindowCloseDelegate?
        private var windowObservers: [NSObjectProtocol] = []
        private let newWindowForTabSelector = NSSelectorFromString("newWindowForTab:")

        init(
            selectedConnectionID: UUID?,
            checkBeforeClosing: Bool,
            connectionController: ConnectionController,
            onWindowBecameKey: @escaping () -> Void,
            onWindowChanged: @escaping (NSWindow) -> Void,
            onTabBarVisibilityChanged: @escaping (Bool) -> Void,
            onRequestDismiss: @escaping () -> Void
        ) {
            self.selectedConnectionID = selectedConnectionID
            self.checkBeforeClosing = checkBeforeClosing
            self.connectionController = connectionController
            self.onWindowBecameKey = onWindowBecameKey
            self.onWindowChanged = onWindowChanged
            self.onTabBarVisibilityChanged = onTabBarVisibilityChanged
            self.onRequestDismiss = onRequestDismiss
        }

        func attach(to view: NSView) {
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let window = view?.window else { return }
                guard self.observedWindow !== window else {
                    self.syncDelegateState()
                    self.onWindowChanged(window)
                    self.updateTabBarVisibility(for: window)
                    return
                }
                self.observe(window: window)
            }
        }

        private func observe(window: NSWindow) {
            if let previousWindow = observedWindow,
               previousWindow !== window,
               let connectionController {
                connectionController.unregisterWindow(previousWindow)
            }

            window.tabbingMode = .preferred
            window.tabbingIdentifier = "WiredMain"

            if closeDelegate == nil {
                closeDelegate = WindowCloseDelegate()
            }

            // Guard: if another coordinator's WindowCloseDelegate is already installed
            // on this window, do not overwrite it. This can happen transiently during
            // addTabbedWindow when view.window temporarily returns the host window
            // instead of the tab's own NSWindow.
            if let existing = window.delegate as? WindowCloseDelegate,
               existing !== closeDelegate {
                onWindowChanged(window)
                updateTabBarVisibility(for: window)
                return
            }

            observedWindow = window
            closeDelegate?.install(on: window)
            installWindowObservers(for: window)
            syncDelegateState()
            onWindowChanged(window)
            updateTabBarVisibility(for: window)
            scheduleNativeNewTabButtonHiding(for: window)
            // If the window is already key when we first observe it, fire the callback
            // now — we may have missed the didBecomeKeyNotification while setting up
            // (e.g. a sibling tab closed and this window became key before our observers
            // were installed).
            if window.isKeyWindow {
                onWindowBecameKey()
            }
        }

        private func syncDelegateState() {
            closeDelegate?.selectedConnectionID = selectedConnectionID
            closeDelegate?.checkBeforeClosing = checkBeforeClosing
            closeDelegate?.connectionController = connectionController
            closeDelegate?.onRequestDismiss = onRequestDismiss
            if let observedWindow, let connectionController {
                connectionController.registerWindow(observedWindow, for: selectedConnectionID)
            }
        }

        private func installWindowObservers(for window: NSWindow) {
            windowObservers.forEach { NotificationCenter.default.removeObserver($0) }
            windowObservers.removeAll()

            let keyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.onWindowBecameKey()
                    if let window = self?.observedWindow {
                        self?.onWindowChanged(window)
                        self?.updateTabBarVisibility(for: window)
                        self?.scheduleNativeNewTabButtonHiding(for: window)
                    }
                }
            }
            windowObservers.append(keyObserver)

            let closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let observedWindow = self.observedWindow,
                       let connectionController = self.connectionController {
                        connectionController.unregisterWindow(observedWindow)
                    }
                    self.observedWindow = nil
                }
            }
            windowObservers.append(closeObserver)
        }

        private func scheduleNativeNewTabButtonHiding(for window: NSWindow) {
            let delays: [TimeInterval] = [0.0, 0.05, 0.2]

            for delay in delays {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak window] in
                    guard let self, let window else { return }
                    self.hideNativeNewTabButton(in: window)
                    self.updateTabBarVisibility(for: window)
                }
            }
        }

        private func updateTabBarVisibility(for window: NSWindow) {
            let isVisible = (window.tabGroup?.windows.count ?? 0) > 1
            onTabBarVisibilityChanged(isVisible)
        }

        private func hideNativeNewTabButton(in window: NSWindow) {
            guard let root = window.contentView?.superview else { return }
            hideNativeNewTabButton(in: root)
        }

        private func hideNativeNewTabButton(in view: NSView) {
            if let control = view as? NSControl,
               shouldHideNativeNewTabControl(control, in: view) {
                let superview = control.superview
                control.removeFromSuperview()
                superview?.needsLayout = true
                superview?.layoutSubtreeIfNeeded()
                return
            }

            for subview in view.subviews {
                hideNativeNewTabButton(in: subview)
            }
        }

        private func shouldHideNativeNewTabControl(_ control: NSControl, in view: NSView) -> Bool {
            if let action = control.action {
                let actionName = NSStringFromSelector(action).lowercased()
                if action == newWindowForTabSelector || actionName.contains("newwindowfortab") {
                    return true
                }
            }

            if let button = control as? NSButton {
                let tooltip = button.toolTip?.lowercased() ?? ""
                if tooltip.contains("new tab")
                    || tooltip.contains("create a new tab")
                    || tooltip.contains("nouvel onglet")
                    || tooltip.contains("nouveau onglet") {
                    return true
                }

                let className = String(describing: type(of: view)).lowercased()
                if className.contains("tabbar") || className.contains("tabbar") {
                    if button.title.isEmpty || button.title == "+" {
                        return true
                    }
                }
            }

            return false
        }

        deinit {
            windowObservers.forEach { NotificationCenter.default.removeObserver($0) }
            if let observedWindow, let connectionController {
                let window = observedWindow
                let controller = connectionController
                Task { @MainActor in
                    controller.unregisterWindow(window)
                }
            }
        }
    }
}

private final class WindowCloseDelegate: NSObject, NSWindowDelegate {
    weak var connectionController: ConnectionController?
    var selectedConnectionID: UUID?
    var checkBeforeClosing: Bool = true
    // Calls SwiftUI's dismiss() for this window's scene — the only safe way to
    // close one tab without cascading through the AppKit NSWindowTabGroup.
    var onRequestDismiss: (() -> Void)?

    // Set to true while we're programmatically closing one specific tab so that
    // any cascade performClose AppKit fires on sibling tabs is swallowed.
    // Only touched on the main thread.
    static var isHandlingProgrammaticClose: Bool = false

    private weak var originalDelegate: NSWindowDelegate?

    func install(on window: NSWindow) {
        if window.delegate !== self {
            originalDelegate = window.delegate
            window.delegate = self
        }
    }

    @MainActor
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if originalDelegate?.windowShouldClose?(sender) == false {
            return false
        }

        // Swallow any cascade performClose that AppKit fires on sibling tabs while
        // we are already handling a programmatic close for one specific tab.
        if WindowCloseDelegate.isHandlingProgrammaticClose {
            return false
        }

        // If the user is not on the Public Chat tab, Cmd+W navigates back to it.
        // selectedConnectionID is this delegate's own connection; it is set by the
        // coordinator that installed this delegate on this specific NSWindow, making
        // it more reliable than activeConnectionID which is shared and can be
        // overwritten by a sibling coordinator's didBecomeKey callback.
        if let id = selectedConnectionID,
           let runtime = connectionController?.runtime(for: id),
           runtime.selectedTab != .chats {
            runtime.selectedTab = .chats
            return false
        }

        guard checkBeforeClosing,
              let connectionController else {
            return true
        }

        // selectedConnectionID is set directly by the coordinator that owns this
        // NSWindow. Fall back to activeConnectionID and then to any connected session
        // in case the per-window state was cleared after a sibling tab closed.
        // Iterate candidates because activeConnectionID can be non-nil but stale
        // (pointing to a disconnected session), which would cause the ?? chain to
        // short-circuit before firstActiveConnectionID() is ever tried.
        let connectionID: UUID? = {
            let candidates = [selectedConnectionID,
                              connectionController.activeConnectionID,
                              connectionController.firstActiveConnectionID()]
            for candidate in candidates {
                guard let id = candidate else { continue }
                if let r = connectionController.runtime(for: id),
                   r.status == .connected || r.status == .connecting {
                    return id
                }
            }
            return nil
        }()
        guard let connectionID,
              let runtime = connectionController.runtime(for: connectionID) else {
            return true
        }

        let alert = NSAlert()
        alert.messageText = "Active connection"
        alert.informativeText = "Do you want to disconnect the active connection before closing this window/tab?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Disconnect and Close")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            connectionController.disconnect(connectionID: connectionID, runtime: runtime)
            // Switch tab group focus to a sibling BEFORE dismissing so that
            // AppKit transfers focus correctly when this window disappears.
            // Without this, the remaining tab is not the key window and its
            // onWindowBecameKey / connection-view restoration never fires.
            if let tabGroup = sender.tabGroup,
               let sibling = tabGroup.windows.first(where: { $0 !== sender }) {
                tabGroup.selectedWindow = sibling
            }
            // Use SwiftUI's dismiss() to close this window's scene.
            // NSWindow.close() on the host window of a tab group cascades and kills
            // all sibling tabs; SwiftUI dismiss() closes only the calling scene.
            // The isHandlingProgrammaticClose flag suppresses any cascade
            // windowShouldClose that AppKit may still fire on siblings.
            WindowCloseDelegate.isHandlingProgrammaticClose = true
            DispatchQueue.main.async {
                WindowCloseDelegate.isHandlingProgrammaticClose = false
                // After the scene has had a chance to close, ensure the next
                // visible window is key so its connection view is fully active.
                NSApp.windows.first { $0.isVisible && !($0 is NSPanel) }?
                    .makeKeyAndOrderFront(nil)
            }
            onRequestDismiss?()
            return false
        default:
            return false
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        originalDelegate?.windowDidBecomeKey?(notification)
    }

    func windowDidResignKey(_ notification: Notification) {
        originalDelegate?.windowDidResignKey?(notification)
    }

    @objc
    func windowWillOrderOnScreen(_ notification: Notification) {
        // Keep empty on purpose: some AppKit paths send this selector to the window delegate
        // even though it's not exposed through NSWindowDelegate in Swift.
    }

    @objc
    func window(_ window: NSWindow, newWindowForTab sender: Any?) -> NSWindow? {
        connectionController?.presentNewConnection()
        return nil
    }
}
#endif

private struct TrackerServerInfoView: View {
    let server: TrackerServerNode

    var body: some View {
        Form {
            Section {
                LabeledContent("Name") {
                    Text(server.name)
                }

                if !server.serverDescription.isEmpty {
                    LabeledContent("Description") {
                        Text(server.serverDescription)
                            .multilineTextAlignment(.trailing)
                    }
                }

                LabeledContent("URL") {
                    Text(server.urlString)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Category") {
                    Text(server.categoryPath.isEmpty ? "None" : server.categoryPath)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Tracker") {
                    Text(server.isTracker ? "Yes" : "No")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                LabeledContent("Users") {
                    Text("\(server.users)")
                }

                LabeledContent("Files") {
                    Text("\(server.filesCount)")
                }

                LabeledContent("Size") {
                    Text(byteCountFormatter.string(fromByteCount: Int64(server.filesSize)))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}
