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
#if os(macOS)
import AppKit
#endif

struct MainView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query private var bookmarks: [Bookmark]
    @Environment(ConnectionController.self) private var connectionController
    @EnvironmentObject private var transfers: TransferManager

    @State private var windowConnectionID: UUID? = nil
    @State private var listSelectionID: UUID? = nil
    @State private var editedBookmark: Bookmark? = nil
    
    @State private var showDeleteBookmarkConfirmation: Bool = false
    @State private var bookmarkToDelete: Bookmark? = nil

    @AppStorage("transfersHeight") private var transfersHeight: Double = 0
    @AppStorage("CheckActiveConnectionsBeforeClosingWindowTab")
    private var checkActiveConnectionsBeforeClosingWindowTab: Bool = true
    @State private var lastTransfersHeight: CGFloat = 200
    @State private var isTransfersVisible = false
    @State private var isTabBarVisible = false
    @State private var windowNumber: Int? = nil

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

    private var tabTitle: String {
        let baseTitle = windowConnectionName ?? "Wired 3"

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

    private var listSelectionBinding: Binding<UUID?> {
        Binding(
            get: { listSelectionID },
            set: { newValue in
                listSelectionID = newValue
                guard let newValue else { return }

#if os(macOS)
                guard connectionController.hasWindowAssociation(for: newValue) else { return }
                if connectionController.focusWindow(for: newValue) {
                    // Keep local selection tied to this window's connection.
                    listSelectionID = windowConnectionID
                    return
                }
                // Do not replace current detail when we cannot focus an existing tab/window.
                return
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
                        listSelectionID = windowConnectionID
                    },
                    onWindowChanged: { window in
                        windowNumber = window.windowNumber
                    },
                    onTabBarVisibilityChanged: { isVisible in
                        isTabBarVisible = isVisible
                    }
                )
                .frame(width: 0, height: 0)
            )
            #endif
            .sheet(item: newConnectionSheetBinding) { draft in
                NewConnectionFormView(draft: draft) { id in
                    connectionController.suppressPresentedNewConnectionSheet = true
                    connectionController.requestedSelectionID = id
                    openMainTab()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        connectionController.suppressPresentedNewConnectionSheet = false
                    }
                }
            }
            .onAppear {
                performInitialLaunchFlowIfNeeded()
                consumePendingSelectionIfNeeded()
                restoreWindowConnectionIfNeeded()
                listSelectionID = windowConnectionID
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
        NavigationSplitView {
            sidebarContent
                #if os(macOS)
                .padding(.top, isTabBarVisible ? 30 : 0)
                .navigationSplitViewColumnWidth(min: 180, ideal: 200)
                #endif
        } detail: {
            detailPane(for: windowConnectionID)
        }
        .toolbar {
            mainToolbar
        }
        .sheet(item: $editedBookmark) { bookmark in
            BookmarkFormView(bookmark: bookmark)
        }
        .alert("Delete Bookmark", isPresented: $showDeleteBookmarkConfirmation) {
            Button("Cancel", role: .cancel) {
            }

            Button("Delete", role: .destructive) {
                deleteBookmark()
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
                    .navigationTitle("Wired 3")
                    .toolbar {
                        mainToolbar
                    }
            }
        }
        .sheet(item: $editedBookmark) { bookmark in
            BookmarkFormView(bookmark: bookmark)
        }
        .alert("Delete Bookmark", isPresented: $showDeleteBookmarkConfirmation) {
            Button("Cancel", role: .cancel) {
            }

            Button("Delete", role: .destructive) {
                deleteBookmark()
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
    }

    @ViewBuilder
    private var connectionList: some View {
        #if os(macOS)
        List(selection: listSelectionBinding) {
            connectionSections
        }
        .contextMenu(forSelectionType: UUID.self) { selection in
            connectionContextMenu(for: selection)
        } primaryAction: { selection in
            handleConnectionPrimaryAction(selection)
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
                        selectConnection(bookmark.id)
                    } label: {
                        connectionRow(connectionID: bookmark.id, name: bookmark.name)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Favorites")
            }

            if !connectionController.temporaryConnections.isEmpty {
                Section {
                    ForEach(connectionController.temporaryConnections, id: \.id) { temporary in
                        Button {
                            selectConnection(temporary.id)
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
                    .tag(bookmark.id)
            }
        } header: {
            Text("Favorites")
        }

        if !connectionController.temporaryConnections.isEmpty {
            Section {
                ForEach(connectionController.temporaryConnections, id: \.id) { temporary in
                    connectionRow(connectionID: temporary.id, name: temporary.name)
                        .tag(temporary.id)
                }
            } header: {
                Text("Connections")
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
            .foregroundStyle(isTransfersVisible ? .blue : .black)
            .buttonStyle(.plain)
            .help("Show Transfers")

            Spacer()
        }
        .padding(9)
    }

    private func connectionRow(connectionID: UUID, name: String) -> some View {
        ConnectionRowView(connectionID: connectionID, name: name)
            .environment(connectionController)
#if os(iOS)
            .contentShape(Rectangle())
            .contextMenu {
                connectionContextMenu(for: Set([connectionID]))
            }
#endif
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
            Button("Connections") {
                windowConnectionID = nil
                listSelectionID = nil
                connectionController.activeConnectionID = nil
            }
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
        ToolbarItem {
            Button {
                #if os(macOS)
                connectionController.presentedNewConnectionWindowNumber = windowNumber
                #endif
                connectionController.presentNewConnection()
            } label: {
                Label("New Connection", systemImage: "plus")
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
        if let bookmarkToDelete  {
            // disconnect if needed
            if let runtime = connectionController.runtime(for: bookmarkToDelete.id) {
                connectionController.disconnect(connectionID: bookmarkToDelete.id, runtime: runtime)
            }
            
            modelContext.delete(bookmarkToDelete)
            self.bookmarkToDelete = nil
        }
        
        showDeleteBookmarkConfirmation = false
    }
    
    private func disconnect(_ id:UUID) {
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
        listSelectionID = requested
        connectionController.requestedSelectionID = nil
        connectionController.activeConnectionID = requested
    }

    private func restoreWindowConnectionIfNeeded() {
        guard windowConnectionID == nil else { return }

        if let listSelectionID,
           hasConnectionContext(listSelectionID) {
            windowConnectionID = listSelectionID
            connectionController.activeConnectionID = listSelectionID
            return
        }

        if let firstActive = connectionController.firstActiveConnectionID() {
            windowConnectionID = firstActive
            listSelectionID = firstActive
            connectionController.activeConnectionID = firstActive
        }
    }

    private func performInitialLaunchFlowIfNeeded() {
        guard !connectionController.didPerformInitialLaunchFlow else { return }
        connectionController.didPerformInitialLaunchFlow = true

        let startupBookmarks = bookmarks.filter { $0.connectAtStartup }
        guard !startupBookmarks.isEmpty else {
            connectionController.presentNewConnection()
            return
        }

        if let first = startupBookmarks.first {
            windowConnectionID = first.id
            listSelectionID = first.id
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
            // If we cannot resolve an existing tab/window for this active connection,
            // avoid replacing the current detail content.
            return
#else
            windowConnectionID = bookmark.id
            listSelectionID = bookmark.id
            connectionController.activeConnectionID = bookmark.id
            return
#endif
        }

        // Reuse the empty main window for the first connection.
        if windowConnectionID == nil {
            windowConnectionID = bookmark.id
            listSelectionID = bookmark.id
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
        listSelectionID = id
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

    @ViewBuilder
    private func connectionContextMenu(for selection: Set<UUID>) -> some View {
        if let id = selection.first {
            if let bookmark = bookmark(for: id) {
                if connectionController.isConnected(id) {
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

                if connectionController.isConnected(id) {
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
            listSelectionID = id
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
        listSelectionID = id
        connectionController.activeConnectionID = id
        connectionController.connect(configuration)
    }

    private func handleConnectionPrimaryAction(_ selection: Set<UUID>) {
        guard let id = selection.first else { return }
        if let bookmark = bookmark(for: id) {
            if connectionController.isConnected(id) {
                openOrSelectBookmark(bookmark)
            } else {
                connectInNewTab(bookmark)
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
        listSelectionID = id
        connectionController.activeConnectionID = id
    }

    private func hasConnectionContext(_ id: UUID) -> Bool {
        connectionController.runtime(for: id) != nil || connectionController.isConnected(id)
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
            listSelectionID = requested
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
            sourceWindow.tabbingMode = .disallowed
            newWindow.tabbingMode = .disallowed
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
        listSelectionID = bookmark.id
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
        listSelectionID = bookmark.id
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
        context.coordinator.attach(to: nsView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            selectedConnectionID: selectedConnectionID,
            checkBeforeClosing: checkBeforeClosing,
            connectionController: connectionController,
            onWindowBecameKey: onWindowBecameKey,
            onWindowChanged: onWindowChanged,
            onTabBarVisibilityChanged: onTabBarVisibilityChanged
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
            onTabBarVisibilityChanged: @escaping (Bool) -> Void
        ) {
            self.selectedConnectionID = selectedConnectionID
            self.checkBeforeClosing = checkBeforeClosing
            self.connectionController = connectionController
            self.onWindowBecameKey = onWindowBecameKey
            self.onWindowChanged = onWindowChanged
            self.onTabBarVisibilityChanged = onTabBarVisibilityChanged
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

            window.tabbingMode = .disallowed
            window.tabbingIdentifier = "WiredMain"

            observedWindow = window
            if closeDelegate == nil {
                closeDelegate = WindowCloseDelegate()
            }
            closeDelegate?.install(on: window)
            installWindowObservers(for: window)
            syncDelegateState()
            onWindowChanged(window)
            updateTabBarVisibility(for: window)
            scheduleNativeNewTabButtonHiding(for: window)
        }

        private func syncDelegateState() {
            closeDelegate?.selectedConnectionID = selectedConnectionID
            closeDelegate?.checkBeforeClosing = checkBeforeClosing
            closeDelegate?.connectionController = connectionController
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

        guard checkBeforeClosing,
              let connectionController else {
            return true
        }

        let senderActiveConnectionIDs = connectionController.activeConnectedConnectionIDs(in: [sender])
        guard !senderActiveConnectionIDs.isEmpty else {
            return true
        }

        let activeConnectionIDs = senderActiveConnectionIDs
        let isSingleConnection = activeConnectionIDs.count == 1

        let alert = NSAlert()
        alert.messageText = isSingleConnection ? "Active connection" : "Active connections"
        alert.informativeText = isSingleConnection
            ? "Do you want to disconnect the active connection before closing this window/tab?"
            : "Do you want to disconnect \(activeConnectionIDs.count) active connections before closing this window/tab?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Disconnect and Close")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            for id in activeConnectionIDs {
                if let runtime = connectionController.runtime(for: id) {
                    connectionController.disconnect(connectionID: id, runtime: runtime)
                }
            }
            return true
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
